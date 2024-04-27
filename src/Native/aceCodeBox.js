let editorDiv = document.createElement("div");
editorDiv.id = "editor";
editorDiv.style.setProperty('position','fixed');
document.getElementById("body").appendChild(editorDiv);

let editor = ace.edit("editor");
editor.setFontSize("13px");
editor.session.setMode("ace/mode/elm");
editor.getSession().setValue("main = [];");

let exebtn = document.getElementById("execute-button");
exebtn.onclick = function() {
    app.ports.exeCode.send(editor.getSession().getDocument().getValue());
};

app.ports.retNewCode.subscribe(function(newCode) {
    editor.getSession().setValue(newCode);
});

let redobtn = document.getElementById("delta-redo-button");
redobtn.onclick = function() {
    app.ports.parseCode.send(editor.getSession().getDocument().getValue());
};


app.ports.retCodeFile.subscribe(function(fileN) {
    if (fileN === "New File") {
        editor.getSession().setValue("");
    } else {
        readTextFile("FuseDMI/src/Examples/" + fileN + ".txt", function(text) {
            editor.getSession().setValue(text);});
    }
});