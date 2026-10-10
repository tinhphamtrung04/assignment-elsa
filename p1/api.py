from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import random
import time

QUOTES = [
    "The best way to get started is to quit talking and begin doing.",
    "Don't let yesterday take up too much of today.",
    "It's not whether you get knocked down, it's whether you get up.",
    "If you are working on something that you really care about, you don't have to be pushed."
]

# Simple in-memory Prometheus counters
metrics_store = {
    ("healthz", "200"): 0,
    ("readyz", "200"): 0,
    ("quote", "200"): 0
}

class APIHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            metrics_store[("healthz", "200")] += 1
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")

        elif self.path == "/readyz":
            metrics_store[("readyz", "200")] += 1
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"READY")

        elif self.path == "/api/quote":
            # Simulate ~100ms of CPU-bound work
            end_time = time.time() + 0.1
            while time.time() < end_time:
                _ = 123456 * 654321  # Busy loop

            quote = random.choice(QUOTES)
            payload = json.dumps({"quote": quote}).encode("utf-8")
            
            metrics_store[("quote", "200")] += 1
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)

        elif self.path == "/metrics":
            output = []
            for (endpoint, status), count in metrics_store.items():
                output.append(f'http_requests_total{{path="/{endpoint}",status="{status}"}} {count}')
            
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers()
            self.wfile.write(("\n".join(output) + "\n").encode("utf-8"))

        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default noisy stdout logs for cleanliness
        return

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), APIHandler)
    server.serve_forever()