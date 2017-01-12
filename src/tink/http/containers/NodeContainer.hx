package tink.http.containers;

import tink.http.Container;
import tink.http.Request;
import tink.http.Header;
import tink.io.*;
import js.node.http.*;

using tink.CoreApi;

class NodeContainer implements Container {
  
  var kind:ServerKind;
  
  public function new(kind:ServerKind) {
    this.kind = kind;
  }
  
  static public function toNodeHandler(handler:Handler)
    return 
      function (req:IncomingMessage, res:ServerResponse)
        handler.process(
          new IncomingRequest(
            req.socket.remoteAddress, 
            new IncomingRequestHeader(cast req.method, req.url, req.httpVersion, [for (i in 0...Std.int(req.rawHeaders.length / 2)) new HeaderField(req.rawHeaders[2 * i], req.rawHeaders[2 * i +1])]), 
            Plain(Source.ofNodeStream('Incoming HTTP message from ${req.socket.remoteAddress}', req)))
        ).handle(function (out) {
          res.writeHead(out.header.statusCode, out.header.reason, cast [for (h in out.header.fields) [(h.name : String), h.value]]);//TODO: readable status code
          out.body.pipeTo(Sink.ofNodeStream('Outgoing HTTP response to ${req.socket.remoteAddress}', res)).handle(function (x) {
            res.end();
          });
        });
  
  
  public function run(handler:Handler) 
    return Future.async(function (cb) {
      var failures = Signal.trigger();
      
      var server = switch kind {
        case Instance(server):
          server;
          
        case Port(port):
          var server = new Server();
          server.listen(port);
          server;
          
        case Host(host):
          var server = new Server();
          server.listen(host.port, host.name);
          server;
          
        case Path(path):
          var server = new Server();
          server.listen(path);
          server;
          
        case Fd(fd):
          var server = new Server();
          server.listen(fd);
          server;
      }
      
      function tinkify(e:js.Error)
        return Error.withData(e.message, e);
        
      function onListen() {
        cb(Running({ 
          shutdown: function (hard:Bool) {
            if (hard)
              trace('Warning: hard shutdown not implemented');
              
            return Future.async(function (cb) {
              server.close(function () cb(Noise));
            });
          },
          failures: failures,//TODO: these need to be triggered
        }));
      }
      
      if(untyped server.listening) // .listening added in v5.7.0, not added to hxnodejs yet
        onListen()
      else
        server.on('listening', onListen);
      
      server.on('request', toNodeHandler(handler));
      server.on('error', function(e) cb(Failed(e)));
    });
}

private enum ServerKindBase {
  Instance(server:Server);
  Port(port:Int);
  Host(host:tink.url.Host);
  Path(path:String);
  Fd(fd:{fd:Int});
}

abstract ServerKind(ServerKindBase) from ServerKindBase to ServerKindBase {
  @:from
  public static function fromInstance(server:Server):ServerKind
    return Instance(server);
    
  @:from
  public static inline function fromPort(port:Int):ServerKind
    return Port(port);
  
  @:from
  public static function fromHost(host:tink.url.Host):ServerKind
    return Host(host);
  
  @:from
  public static function fromPath(path:String):ServerKind
    return Path(path);
  
  @:from
  public static function fromFd(fd:{fd:Int}):ServerKind
    return Fd(fd);
}