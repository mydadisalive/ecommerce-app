from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route("/register", methods=["POST"])
def register():
    data = request.get_json()
    # Register user logic here
    return jsonify({"message": "User registered!"}), 201

@app.route("/login", methods=["POST"])
def login():
    data = request.get_json()
    # Authenticate user logic here
    return jsonify({"message": "User authenticated!"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
