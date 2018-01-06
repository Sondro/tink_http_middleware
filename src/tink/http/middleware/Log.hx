package tink.http.middleware;

import tink.http.Request;
import tink.http.Response;
import tink.http.Middleware;
import tink.http.Handler;
import tink.http.Method;

using StringTools;
using tink.CoreApi;
using tink.io.Source;

class Log implements MiddlewareObject {
	var logger:Logger;
	var skip:Array<EReg>;
	
	public function new(?logger, ?skip) {
		this.logger = if(logger == null) new DefaultLogger() else logger;
		this.skip = skip == null ? [] : skip;
	}
	
	public function apply(handler:Handler):Handler
		return new LogHandler(logger, skip, handler);
}

class LogHandler implements HandlerObject {
	var logger:Logger;
	var skip:Array<EReg>;
	var handler:Handler;
	
	public function new(logger, skip, handler) {
		this.logger = logger;
		this.skip = skip;
		this.handler = handler;
	}
	
	public function process(req:IncomingRequest) {
		// skip logger if matched uri prefix
		var uri = req.header.url.path.toString();
		for(s in skip) if(s.match(uri)) return handler.process(req);
		
		var start = stamp();
		logger.log(HttpIn(req));
		var res = handler.process(req);
		res.handle(function(res) {
			logger.log(HttpOut(req, res, stamp() - start));
			if(res.header.statusCode.toInt() >= 400)
				res.body.all().handle(function(o) Sys.println(o.toString()));
		});
		return res;
	}
	
	static function stamp()
		return Std.int(haxe.Timer.stamp() * 1000);
}

enum LogMessage {
	HttpIn(req:IncomingRequest);
	HttpOut(req:IncomingRequest, res:OutgoingResponse, duration:Int);
}

class LogMessageFormatter {
	public static function format(message:LogMessage, verbose:Bool) {
		var buf = new StringBuf();
		inline function addSegment(s:String) {
			buf.add(s);
			buf.add(' | ');
		}
		
		addSegment(Date.now().toString());
		
		switch message {
			case HttpIn(req):
				addSegment('IN'.rpad(' ', 8));
				addSegment((req.header.method:String).rpad(' ', 8));
				addSegment(''.rpad(' ', 5));
				buf.add(req.header.url.pathWithQuery);
				if(verbose) {
					for(header in req.header) buf.add('\n  ' + header.name + ': ' + header.value);
				}
			case HttpOut(req, res, duration):
				addSegment('OUT ${res.header.statusCode.toInt()}'.rpad(' ', 8));
				addSegment((req.header.method:String).rpad(' ', 8));
				addSegment((duration + 'ms').rpad(' ', 5));
				buf.add(req.header.url.pathWithQuery);
				if(verbose) {
					for(header in res.header) buf.add('\n  ' + header.name + ': ' + header.value);
				}
		}
		return buf.toString();
	}
}

interface Logger {
	function log(message:LogMessage):Void;
}

class DefaultLogger implements Logger {
	var verbose:Bool;
	public function new(verbose = false) {
		this.verbose = verbose;
	}
	
	public function log(message:LogMessage)
		Sys.println(LogMessageFormatter.format(message, verbose));
}
