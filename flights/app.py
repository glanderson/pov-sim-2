from flasgger import Swagger
from flask import Flask, jsonify, request
from flask_cors import CORS
from utils import get_random_int

import logging
from uuid import uuid4
from opentelemetry import trace
from opentelemetry import metrics
from random import randint

import os
import pyroscope

pyroscope.configure(
    application_name     = os.environ.get("PYROSCOPE_APPLICATION_NAME"),
    server_address       = os.environ.get("PYROSCOPE_SERVER_ADDRESS"),
    basic_auth_username  = os.environ.get("PYROSCOPE_BASIC_AUTH_USER"),
    basic_auth_password  = os.environ.get("PYROSCOPE_BASIC_AUTH_PASSWORD"),
)

# Acquire a tracer
tracer = trace.get_tracer("flights.tracer")
# Acquire a meter.
meter = metrics.get_meter("flights.meter")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

flight_check_counter = meter.create_counter(
    "flights.checks",
    description="The number of calls to the /flights endpoint",
)

app = Flask(__name__)
Swagger(app)
CORS(app)

@app.route('/health', methods=['GET'])
def health():
    """Health endpoint
    ---
    responses:
      200:
        description: Returns healthy
    """
    return jsonify({"status": "healthy"}), 200

@app.route("/", methods=['GET'])
def home():
    """No-op home endpoint
    ---
    responses:
      200:
        description: Returns ok
    """
    return jsonify({"message": "ok"}), 200

@app.route("/flights/<airline>", methods=["GET"])
def get_flights(airline):
    """Get flights endpoint. Optionally, set raise to trigger an exception.
    ---
    parameters:
      - name: airline
        in: path
        type: string
        enum: ["AA", "UA", "DL"]
        required: true
      - name: raise
        in: query
        type: str
        enum: ["500"]
        required: false
    responses:
      200:
        description: Returns a list of flights for the selected airline
    """
    status_code = request.args.get("raise")
    if status_code:
      raise Exception(f"Encountered {status_code} error") # pylint: disable=broad-exception-raised
    random_int = get_random_int(100, 999)
    
    with tracer.start_as_current_span("flights", kind=trace.SpanKind.SERVER) as flight_span:
        # trace span
        flight_span.set_attribute("airline", airline)
        # metric
        flight_check_counter.add(1, {"airline": 1})
        # log
        logmsg = "flights checked for airline: " + airline
        logger.info(logmsg)
        
    return jsonify({airline: [random_int]}), 200     

@app.route("/flight", methods=["POST"])
def book_flight():
    """Book flights endpoint. Optionally, set raise to trigger an exception.
    ---
    parameters:
      - name: passenger_name
        in: query
        type: string
        enum: ["John Doe", "Jane Doe"]
        required: true
      - name: flight_num
        in: query
        type: string
        enum: ["101", "202", "303", "404", "505", "606"]
        required: true
      - name: raise
        in: query
        type: str
        enum: ["500"]
        required: false
    responses:
      200:
        description: Booked a flight for the selected passenger and flight_num
    """
    status_code = request.args.get("raise")
    if status_code:
      raise Exception(f"Encountered {status_code} error") # pylint: disable=broad-exception-raised
    passenger_name = request.args.get("passenger_name")
    flight_num = request.args.get("flight_num")
    booking_id = get_random_int(100, 999)
    return jsonify({"passenger_name": passenger_name, "flight_num": flight_num, "booking_id": booking_id}), 200

if __name__ == "__main__":
    app.run(debug=True, port=5001)
