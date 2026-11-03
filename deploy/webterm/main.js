var term,
    protocol,
    socketURL,
    socket;

var terminalContainer = document.getElementById('terminal-container');

createTerminal(getParameterByName("host"), getParameterByName("port"), getParameterByName("password"));

function getParameterByName(name, url) {
    if (!url) url = window.location.href;
    name = name.replace(/[\[\]]/g, "\\$&");
    var regex = new RegExp("[?&]" + name + "(=([^&#]*)|&|#|$)"),
        results = regex.exec(url);
    if (!results) return '';
    if (!results[2]) return '';
    return decodeURIComponent(results[2].replace(/\+/g, " "));
}

function createTerminal(host, port, password) {
    while (terminalContainer.children.length) {
        terminalContainer.removeChild(terminalContainer.children[0]);
    }
    term = new Terminal({
        cursorBlink: true
    });
    protocol = (location.protocol === 'https:') ? 'wss://' : 'ws://';
    socketURL = protocol + location.hostname + ((location.port) ? (':' + location.port) : '') + '/bash?host=' + host + "&password=" + password + "&port=" + port;
    socket = new WebSocket(socketURL);

    term.open(terminalContainer);
    term.fit();
    term.toggleFullscreen(true);

    socket.onopen = runRealTerminal;
    socket.onclose = runFakeTerminal;
    socket.onerror = runFakeTerminal;
}


function runRealTerminal() {
    term.attach(socket);
    term._initialized = true;
}

function runFakeTerminal() {
    if (term._initialized) {
        return;
    }
    term._initialized = true;
    term.writeln('You are not allowed to access to this machine, or another error occured');
}
