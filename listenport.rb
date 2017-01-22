#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'optparse'
require 'json'

def usage(args)
#23456789+123456789+123456789+123456789+123456789+123456789+123456789+123456789+
puts <<EOF
サーバー再起動する前後のポート状態を調べるツールです。
Usage: #{File.basename($0)} [-t PERCENT] [-e MOUNTS] [-m MAILTO] [HOST]

Options:
  -u, --udp-ports=PORT1[,PORT2...]
                             UDP ポートをチェックします。
                             複数のポート番号をカンマ区切りで指定します。
                             デフォルトで UDP ポートはチェックしません。

  -x, --unix-socket=SOCKETPATH1[,SOCKETPATH2...]
                             unix socket ファイルをチェックします。
                             複数指定する場合はカンマで区切ります。
                             デフォルトではチェックしません。

  -i, --ignore-program=NAME1[,NAME2...]
                             無視するプログラムを指定。
                             rpc.statd など、起動する毎に変わるポート番号を無視します。
                             デフォルトは #{args[:ignore_programs].join(",")} です。

  -c, --check                チェックモードをオンにします。
                             デフォルトはオフです。
                             チェックモードオフは再起動前に情報収集するために使います。
                             チェックモードオンは再起動後にチェックするために使います。

  -i, --input=FILE           チェックモードオンの時、前回出力したファイルを指定します。
                             チェックモードオンの場合は必須です。

  -o, --ooutput=FILE         チェックモードオフの時、収集した情報を出力します。
                             このオプションを指定しない場合は標準出力に出力します。

  --pretty                   人間に読みやすい形式で出力します。
                             このオプションをつけて出力したファイルをチェックモードで使用することはできません。

デフォルトでは TCP,UDP ポートを調べます。

例:
 #{File.basename($0)} -o hoge.json -x /run/rpcbind.sock
 #{File.basename($0)} -i hoge.json --check
EOF
  exit 1
end

args={}
args[:unix_sockets] = []
args[:ignore_programs] = ["rpc.statd", "rpcbind", "dhclient"]
args[:checkmode] = false
args[:ifile] = nil
args[:ofile] = nil
args[:pretty] = false
OptionParser.new { |opt|
  opt.on("-x", "--unix-socket=SOCKETPATHS") {|v|
    args[:unix_sockets] += v.split(/,/).map(&:strip)
  }
  opt.on("-i", "--ignore-program=NAMES") {|v|
    args[:ignore_programs] += v.split(/,/).map(&:strip)
  }
  opt.on("-c", "--check") {args[:checkmode] = true}
  opt.on("-i", "--input==FILE") {|v| args[:ifile] = v}
  opt.on("-o", "--output==FILE") {|v| args[:ofile] = v}
  opt.on("--pretty") {|v| args[:pretty] = true}
  opt.on("-h", "--help") {usage(args)}
  opt.parse!(ARGV)
}

def filter(h, args)
  return true if args[:ignore_programs].include?(h[:program])
  false
end

def format(ports, pretty=false)
  return ports.to_json if !pretty
  lines = []
  lines << "TYPE  PORT BINDIP            PID USER       PROGRAM          PATH"
  ports.each do |port|
    type = port[:type].to_s
    type += "6" if port[:ipv6]
    lines << sprintf("%-5s%5s %-15.15s %5s %-10.10s %-16.16s %s",
                     type, port[:port], port[:bindip], port[:pid], port[:owner], port[:program], port[:path])
  end
  lines.join("\n")
end

def format_detail(ports)
  lines = []
  ports.each do |port|
    title = port[:type].to_s.upcase
    title += " PORT:#{port[:port]}" if port[:type] != :unix
    title += " PATH:#{port[:path]}" if port[:type] == :unix
    lines << title
    lines << "-" * title.length
    lines << "TYPE    : #{port[:type]}"
    lines << "IPV6    : #{port[:ipv6]}" if port[:type] != :unix
    lines << "PORT    : #{port[:port]}" if port[:type] != :unix
    lines << "BINDIP  : #{port[:bindip]}" if port[:type] != :unix
    lines << "USER    : #{port[:owner]}"
    lines << "PROGRAM : #{port[:program]}"
    lines << "PATH    : #{port[:path]}" if port[:type] == :unix
    lines << "CWD     : #{port[:cwd]}"
    lines << "EXE     : #{port[:exe]}"
    lines << "CMDLINE : #{port[:cmdline].gsub(/\x0/, " ")}"
    lines << "ENVIRON:"
    lines << port[:environ].split(/\x0/).sort.map(&:strip).tap{|a| a.delete("")}.compact.map {|l| "  " + l}
    lines << ""
  end
  lines.join("\n")
end

def collect(args)
  ports = []
  `netstat -lnp`.each_line do |l|
    l = l.chomp.strip
    if l =~ /tcp([6]?)\s+\S+\s+\S+\s+(\S+):(\S+).*LISTEN\s+(\d+)\/(.+)$/
      h = {type: :tcp, ipv6: ($1 == "6"), bindip: $2, port: $3, pid: $4, program: $5.strip}
      ports << h unless filter(h, args)
    end
    if l =~ /udp([6]?)\s+\S+\s+\S+\s+(\S+):(\S+).*\s(\d+)\/(.+)$/
      h = {type: :udp, ipv6: ($1 == "6"), bindip: $2, port: $3, pid: $4, program: $5.strip}
      ports << h unless filter(h, args)
    end
    if l =~ /unix.*LISTENING.*\s(\d+)\/(.+)\s+(\S.*)$/
      h = {type: :unix, ipv6: nil, bindip: nil, port: nil, pid: $1, program: $2.strip, path: $3.strip}
      ports << h if args[:checkmode] || args[:unix_sockets].include?(h[:path])
    end
  end

  ports.each do |port|
    port[:owner] = `/bin/ls -ld /proc/#{port[:pid]}/`.split[2]
    port[:environ] = File.read("/proc/#{port[:pid]}/environ")
    port[:cmdline] = File.read("/proc/#{port[:pid]}/cmdline")
    port[:cwd] = `readlink /proc/#{port[:pid]}/cwd`.chomp
    port[:exe] = `readlink /proc/#{port[:pid]}/exe`.chomp
  end
end

def readjson(file)
  ports = JSON.parse(File.read(file), symbolize_names: true)
  ports.each do |port|
    port[:type] = port[:type].to_sym
  end
end

ports = collect(args)
if args[:checkmode] == false
  f = args[:ofile] ? File.open(args[:ofile], "w") : STDOUT
  f.puts format(ports, args[:pretty])
  f.close if args[:ofile]
else
  prev = readjson(args[:ifile])
  curr = ports
  notfounds = []
  prev.each do |pport|
    res = curr.find do |cport|
      cport[:type] == pport[:type] &&
      cport[:ipv6] == pport[:ipv6] &&
      cport[:bindip] == pport[:bindip] &&
      cport[:port] == pport[:port] &&
      (pport[:program] !~ /^\d+$/ ? cport[:program] == pport[:program] : true) &&
      (pport[:type] == :unix ? cport[:path] == pport[:path] : true)
    end
    notfounds << pport if res.nil?
  end
  unless notfounds.empty?
    puts "Error: Ports doesn't exists."
    puts
    puts format_detail(notfounds)
    exit 1
  end
end
