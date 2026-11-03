// Vendored from github.com/INGInious/xterm (src/app.js), patched:
// - pty.js -> node-pty (pty.js does not build on modern Node)
// - argv count check fixed (upstream `argv["_"] < 3` is always false due to
//   array-to-string coercion)
// - password auto-fill also disabled when the query param is missing
// - static xterm assets resolved against this directory (app.js lives at the
//   package root here, not in src/)
var express = require('express');
var app = express();
var expressWs = require('express-ws');
var fs = require('fs');
var http = require('http');
var https = require('https');
var pty = require('node-pty');
var argv = require('minimist')(process.argv.slice(2));

function usage() {
  console.log("node app [--certpath=path-to-cert.pem --keypath=path-to-private.key [--capath=path-to-ca.pem]] HOST PORT rhostA:portA-portB,portC [rhostA:portA-portB,portC ...]");
  console.log("Example: node app localhost 3000 localhost:64000-64100 remote.be:22,2222");
  console.log("");
}

/****************************************\
             Arg parse
\****************************************/

var allowed_hosts = {};
var re_host = /^[a-z\d]([a-z\d\-]{0,61}[a-z\d])?(\.[a-z\d]([a-z\d\-]{0,61}[a-z\d])?)*$/i;

// process args
if(argv["_"].length < 3) {
  usage();
  console.log("Not enough parameters");
  process.exit(1);
}

bind_hostname = argv["_"][0];
bind_port = parseInt(argv["_"][1]);
if(isNaN(bind_port)) {
  usage();
  console.log("The port should be an integer");
  process.exit(1);
}

argv["_"].forEach(function (val, index) {
  if(index >= 2) {
    val = val.split(":");
    if(val.length != 2) {
      usage();
      console.log('Hostnames should be in the form hostname.be:2222-2228,2230,2231');
      process.exit(1);
    }
    var hostname = val[0];
    if(hostname.match(re_host) == null) {
      usage();
      console.log('Invalid hostname: ' + hostname);
      process.exit(1);
    }
    var ports = [];
    try {
      val[1].split(",").forEach(function(v) {
        v = v.split("-");
        if(v.length == 2) {
          v[0] = parseInt(v[0]);
          v[1] = parseInt(v[1]);
          if(isNaN(v[0]) || isNaN(v[1])) {
            usage();
            console.log('Hostnames should be in the form hostname.be:2222-2228,2230,2231');
            process.exit(1);
          }
          for(var i = v[0]; i <= v[1]; i++)
            ports.push(i);
        }
        else {
          if(isNaN(v[0])) {
            usage();
            console.log('Hostnames should be in the form hostname.be:2222-2228,2230,2231');
            process.exit(1);
          }
          ports.push(parseInt(v[0]));
        }
      });
      allowed_hosts[hostname] = ports;
    }
    catch(ex) {
      usage();
      console.log('Hostnames should be in the form hostname.be:2222-2228,2230,2231');
      process.exit(1);
    }
  }
});

/****************************************\
             Server creation
\****************************************/

var server = null;
var isHTTPS = false;
//Create a HTTPS server
if(argv["certpath"] != undefined && argv["keypath"] != undefined) {
  options = {
        key: fs.readFileSync( argv["keypath"] ),
        cert: fs.readFileSync( argv["certpath"] )
  };
  if(argv["capath"] != undefined)
    options["ca"] = fs.readFileSync( argv["capath"] );

  isHTTPS = true;
  server = https.createServer(options, app);
}
//Invalid config
else if(argv["certpath"] != undefined || argv["keypath"] != undefined) {
  usage();
  console.log('--certpath and --keypath should be defined together or not at all');
  process.exit(1);
}
//Create a HTTP server
else {
  isHTTPS = false;
  server = http.createServer(app);
}

expressWs(app, server);

/****************************************\
                   Pages
\****************************************/

app.use('/src', express.static(__dirname + '/node_modules/xterm/src'));
app.use('/addons', express.static(__dirname + '/node_modules/xterm/addons'));

app.get('/', function(req, res){
  res.sendFile(__dirname + '/index.html');
});

app.get('/style.css', function(req, res){
  res.sendFile(__dirname + '/style.css');
});

app.get('/main.js', function(req, res){
  res.sendFile(__dirname + '/main.js');
});

app.ws('/bash', function(ws, req) {
  /**
   * Open bash terminal and attach it
   */
  var host = req.query.host;
  var port = parseInt(req.query.port);
  var password = req.query.password;

  if(allowed_hosts[host] == undefined)
  {
    ws.send("Host not allowed");
    return; //nope
  }

  if(allowed_hosts[host].indexOf(port) < 0)
  {
    ws.send("Port not allowed on this host");
    return; //nope
  }

  var term = pty.spawn('ssh', ['worker@'+host,
                               '-p', port,
                               "-o", "UserKnownHostsFile=/dev/null",
                               "-o", "StrictHostKeyChecking=no"],
  {
    name: 'xterm-256color',
    cols: 80,
    rows: 24,
    cwd: process.env.PWD,
    env: process.env
  });

  var waiting_for_password = password != "" && password != undefined; //deactivate if no password
  var waiting_for_password_buff = "";

  term.on('data', function(data) {
    if(waiting_for_password) {
      waiting_for_password_buff += data;
      if(waiting_for_password_buff.endsWith("assword: ")) {
        term.write(password+"\n");
        waiting_for_password = false;
        waiting_for_password_buff = undefined;
      }
    }
    else {
      try {
        ws.send(data);
      } catch (ex) {
        // The WebSocket is not open, ignore
      }
    }
  });
  ws.on('message', function(msg) {
    term.write(msg);
  });
  ws.on('close', function () {
    console.log('close');
    try {
      process.kill(term.pid);
    }
    catch(ex) {
      //ignore
    }

  });
});

/****************************************\
                   Serve
\****************************************/

if(isHTTPS)
  console.log('App listening to https://' + bind_hostname + ':' + bind_port);
else
  console.log('App listening to http://' + bind_hostname + ':' + bind_port);
server.listen(bind_port, bind_hostname);
