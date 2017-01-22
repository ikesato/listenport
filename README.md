概要
====
サーバー再起動する前後のポート状態を調べるツールです。

背景
====
弊社では月１でサーバーのセキュリティパッチをあてる作業をしています。  
主に ubuntu で自動更新しているのですが、サーバー再起動が必要なパッチがあると手動で再起動する必要があります。  
再起動後にあるサービスが起動していないということがないように手動で起動しているかチェックしています。  
この作業が面倒なのでツールを作成しました。  

作業は単純で netstat -lnp を再起動前後で比べるという簡単なチェックです。  

例えば tcp ポートの場合は以下のような出力になります。  
````````````````````````
[vagrant-ubuntu-trusty-64 ikeda listenport]% sudo netstat -lnpt
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 127.0.0.1:6379          0.0.0.0:*               LISTEN      1223/redis-server 1
tcp        0      0 0.0.0.0:111             0.0.0.0:*               LISTEN      771/rpcbind
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      1185/sshd
tcp        0      0 0.0.0.0:58913           0.0.0.0:*               LISTEN      818/rpc.statd
tcp6       0      0 :::59397                :::*                    LISTEN      818/rpc.statd
tcp6       0      0 :::111                  :::*                    LISTEN      771/rpcbind
tcp6       0      0 :::22                   :::*                    LISTEN      1185/sshd
[vagrant-ubuntu-trusty-64 ikeda listenport]%
`````````````````````````

再起動後にポート 6379 が起動していなければ redis-server が起動していないのでまずいということになります。


仕様
----
- 再起動で動的に変わるポート rpc.statd は無視しています。  
詳細は ./listenport.rb --help に記述してあります。  

- デフォルトでは tcp, udp ポートしか調べません。  
docker など入れている場合は unix ソケットをチェックする必要があるのでその場合はコマンドライン引数で指定します。  


使い方
------

- 例. 再起動前の情報収集  
````````
$ sudo ./listenport.rb -o hoge.json -x /var/run/docker.sock,/var/run/docker/libcontainerd/docker-containerd.sock
````````

- 例. 再起動後のチェック  
````````
$ sudo ./listenport.rb -i hoge.json --check
````````
