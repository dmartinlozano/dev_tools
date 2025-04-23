import os
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"

from flask import Flask, render_template, jsonify, send_from_directory, request, Response
from installer import Installer
from tools.config import Config
import uuid
import os
import base64
import threading

app = Flask(__name__)
namespace = "dev-tools"

@app.route("/")
def index():
    return render_template("index.html")

@app.route('/static/<path:filename>')
def static_files(filename):
    static_dir = os.path.join(os.path.dirname(__file__), 'templates', 'static')
    return send_from_directory(static_dir, filename)

@app.route("/installer")
def installer():
    #TODO list installled helms
    return jsonify([]), 200

@app.route("/installer/progress/<progress_id>")
def installer_progress(progress_id):
    def event_stream():
        installer = Installer(progress_id)
        threading.Thread(target=installer.install, daemon=True).start()
        q = installer.get_progress_queue()
        if not q:
            yield f"data: error\n\n"
            return
        while True:
            msg = q.get()
            if msg == 'done':
                yield f"data: done\n\n"
                break
            yield f"data: {msg}\n\n"
    return Response(event_stream(), mimetype="text/event-stream")

@app.route("/installer/prepare", methods=["POST"])
def installer_post():
    form = request.form
    files = request.files
    data = {}
    data['kubeDomain'] = form.get('kubeDomain', '')
    data['adminPassword'] = form.get('adminPassword', '')
    data['certType'] = form.get('certType', '')
    if data['certType'] == 'letsencrypt':
        data['adminEmail'] = form.get('adminEmail', '')
    if data['certType'] == 'custom':
        for field in ['publicCert', 'privateKey', 'caBundle']:
            file = files.get(field)
            if file:
                data[field] = base64.b64encode(file.read()).decode('utf-8')

    Config().create_namespace()
    Config().create_secret(
        secret_name="config", 
        data={k: base64.b64encode(v.encode()).decode('utf-8') if isinstance(v, str) else v for k, v in data.items()}
    )
    progress_id = str(uuid.uuid4())
    return jsonify({"progress_id": progress_id})
    
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)