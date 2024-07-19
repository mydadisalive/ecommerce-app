from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

@app.route('/')
def home():
    return "E-commerce API"

@app.route('/products', methods=['POST'])
def add_product():
    data = request.get_json()
    # Add product to database logic here
    return jsonify({"message": "Product added!"}), 201

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
