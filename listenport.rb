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
                             チェックモードオンは再起動後にチェックするための使います。
                             チェックモードオンの場合 -f で再起動前に出力したポート情報ファイルを指定する必要があります。
  -f, --f=FILE               チェックモードがオフ場合は収集した情報を出力します。
                             このオプションを指定しない場合は標準出力に出力します。
  --pretty                   人間に読みやすい形式で出力します。
                             このオプションをつけて出力したファイルをチェックモードで使用することはできません。

デフォルトでは TCP,UDP ポートを調べます。

例:
 #{File.basename($0)} -e /,/var tyo05
EOF
  exit 1
end

args={}
args[:unix_sockets] = []
args[:ignore_programs] = ["rpc.statd", "rpcbind", "dhclient"]
args[:checkmode] = false
args[:file] = nil
args[:pretty] = false
OptionParser.new { |opt|
  opt.on("-x", "--unix-socket=SOCKETPATHS") {|v|
    args[:unix_sockets] = v.split(/,/).map(&:strip)
  }
  opt.on("-i", "--ignore-program=NAMES") {|v|
    args[:ignore_programs] += v.split(/,/).map(&:strip)
  }
  opt.on("-c", "--check") {args[:checkmode] = true}
  opt.on("-f", "--file==FILE") {|v| args[:file] = v}
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
  lines << "TYPE  PORT BINDIP            PID USER       PROGRAM"
  ports.each do |port|
    type = port[:type].to_s
    type += "6" if port[:ipv6]
    lines << sprintf("%-5s%5d %-15.15s %5s %-10.10s %s", type, port[:port], port[:bindip], port[:pid], port[:owner], port[:program])
  end
  lines.join("\n")
end

if args[:checkmode] == false
  ports = []
  `netstat -lnpt`.each_line do |l|
    if l.chomp.strip =~ /tcp([6]?)\s+\S+\s+\S+\s+(\S+):(\S+).*LISTEN\s+(\d+)\/(.+)$/
      h = {type: :tcp, ipv6: ($1 == "6"), bindip: $2, port: $3, pid: $4, program: $5}
      ports << h unless filter(h, args)
    end
  end

  `netstat -lnpu`.each_line do |l|
    if l.chomp.strip =~ /udp([6]?)\s+\S+\s+\S+\s+(\S+):(\S+).*\s(\d+)\/(.+)$/
      h = {type: :udp, ipv6: ($1 == "6"), bindip: $2, port: $3, pid: $4, program: $5}
      ports << h if !filter(h, args)
    end
  end

  ports.each do |port|
    port[:owner] = `/bin/ls -ld /proc/#{port[:pid]}/`.split[2]
    port[:environ] = File.read("/proc/#{port[:pid]}/environ")
    port[:cmdline] = File.read("/proc/#{port[:pid]}/cmdline")
    port[:cwd] = `readlink /proc/#{port[:pid]}/cwd`.chomp
    port[:exe] = `readlink /proc/#{port[:pid]}/exe`.chomp
  end

  f = args[:file] ? File.open(args[:file], "w") : STDOUT
  f.puts format(ports, args[:pretty])
  f.close if args[:file]
else
  #TODO:
end
