//  Copyright (C) 2023 Texas Instruments Incorporated - http://www.ti.com/
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions
//  are met:
//
//    Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
//    Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the
//    distribution.
//
//    Neither the name of Texas Instruments Incorporated nor the names of
//    its contributors may be used to endorse or promote products derived
//    from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

function getIPAddress() {
    var interfaces = require('os').networkInterfaces();
    for (var devName in interfaces) {
      var iface = interfaces[devName];
  
      for (var i = 0; i < iface.length; i++) {
        var alias = iface[i];
        if (alias.family === 'IPv4' && alias.address !== '127.0.0.1' && !alias.internal)
          return alias.address;
      }
    }
    return '0.0.0.0';
}

function getArgs () {
  const args = {};
  process.argv
      .slice(2, process.argv.length)
      .forEach( arg => {
      // long arg
      if (arg.slice(0,2) === '--') {
          const longArg = arg.split('=');
          const longArgFlag = longArg[0].slice(2,longArg[0].length);
          const longArgValue = longArg.length > 1 ? longArg[1] : true;
          args[longArgFlag] = longArgValue;
      }
      // flags
      else if (arg[0] === '-') {
          const flags = arg.slice(1,arg.length).split('');
          flags.forEach(flag => {
          args[flag] = true;
          });
      }
  });
  return args;
}

var dgram = require('dgram');
var express = require('express')
var http = require('http')
var EventEmitter = require('events').EventEmitter;
let cors = require("cors");
var bodyParser = require('express/node_modules/body-parser')
var IpAddr = getIPAddress();

var app = express();
app.use(express.static(__dirname + '/'));

//Set HTTP and UDP port number
var port = 8080;
var udp_port = 8081;

const args = getArgs();
if (args.udp_port)
  udp_port = args.udp_port
if (args.http_port)
  port = args.http_port

if (udp_port == port){
  console.log("\n[ERROR] Udp port and Http port cannot be same.\n");
  process.exit();
}

//Set Cors settings
const corsOptions = {
    origin: '*',
    optionsSuccessStatus: 200 // For legacy browser support
};
app.use(cors(corsOptions));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Add Access Control Allow Origin headers
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.header(
    "Access-Control-Allow-Headers",
    "Origin, X-Requested-With, Content-Type, Accept"
  );
  next();
});

var httpServer = http.createServer(app);
var emitter = new EventEmitter();

/**
 * send mp4 stream as response whenever
 * data is emitted from udp socket
 */
app.get('/mp4', function (req, res) {
  res.writeHead(200, {
    'Content-Type': 'video/mp4',
  });
  console.log(req.params.id)
  emitter.on('data', function(data) {
      const chunk = data.length
      if(chunk > 0){
          res.write(data)
      }
      else{
      console.log('empty')
      res.status(500).end('stop')
      }
  });

  emitter.on('end', function() {
      console.log('Response closed.');
  res.end();
  });

  console.log('returning...');
});

/**
 * send image stream as response whenever
 * data is emitted from udp socket
 */
app.get('/jpeg', function (req, res) {
  res.writeHead(200, {
      'Content-Type': 'multipart/x-mixed-replace;boundary=--spionisto',
  });
  console.log(req.params.id)
  emitter.on('data', function(data) {
       const chunk = data.length
       if(chunk > 0){
        res.write(data)
       }
       else{
        res.status(500).end('stop')
       }
  });

  emitter.on('end', function() {
    res.end();
  });

  console.log('returning...');
});

/**Stop udp server from sending pending data after
 *deleting pipeline
 */
app.get('/test', function (req, res) {
   emitter.emit('data', '');
   res.status(200).send('Stopped stream')

});

async function myResponse(req, res) {
    console.log(new Date().getTime() + " GET request => " + req.originalUrl);
    await asyncForLoop();
    console.log(new Date().getTime() + " finished for-loop.");
}

async function asyncForLoop() {
    for (let i=0; i<5; i++) {
        console.log(i);
        await wait(1000);
    }
}

function wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

const udpServer = dgram.createSocket('udp4');

udpServer.on('error', (err) => {
  console.log(`server error:\n${err.stack}`);
  udpServer.close();
});

//Emit video data received from gstreamer
udpServer.on('message', (msg, rinfo) => {
  emitter.emit('data', msg);
});

udpServer.on('listening', () => {
  const address = udpServer.address();
  console.log(`UDP Server listening at port ${address.port}`);
});

udpServer.bind(udp_port);

httpServer.listen(port);

console.log(`\nView Jpeg encoded frames at http://${IpAddr}:${port}/jpeg\n`)
console.log(`View H264 encoded frames at http://${IpAddr}:${port}/mp4\n`)

process.on('uncaughtException', function (err) {
    console.log(err);
});