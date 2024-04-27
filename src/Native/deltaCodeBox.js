let deltaEditorDiv = document.createElement("div");
deltaEditorDiv.id = "deltaEditor"
document.getElementById("body").appendChild(deltaEditorDiv);

let deltaEditor = ace.edit("deltaEditor");
deltaEditor.setFontSize("13px");
deltaEditor.session.setMode("ace/mode/elm");
// deltaEditor.getSession().setValue("(+55)::(+44)::id");
deltaEditor.getSession().setValue("");

let bxbtn = document.getElementById("delta-back-button");
bxbtn.onclick = function() {
    let deltaStr = deltaEditor.getSession().getDocument().getValue();
    console.log("deltaStr:", deltaStr);
    app.ports.getEdit.send(deltaStr);
};


let undobtn = document.getElementById("delta-undo-button");
undobtn.onclick = function() {
    app.ports.undoCode.send("");
};

