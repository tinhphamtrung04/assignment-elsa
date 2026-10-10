from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import random
import time
import sys

# Global metrics counter
REQUEST_COUNT = 0

QUOTES = [
    "The secret of getting ahead is getting started. – Mark Twain",
    "Don't watch the clock; do what it does. Keep going. – Sam Levenson",
    "You don't have to be great to start, but you have to start to be great. – Zig Ziglar",
    "Everything you've ever wanted is on the other side of fear. – George Addair",
    "Success usually comes to those who are too busy to be looking for it. – Henry David Thoreau"
]

class APIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Format logs for container runtime stdout/stderr
        sys.stdout.write(f"[{self.log_date_time_string()}] {self.client_address[0]} - {format % args}\n")
        sys.stdout.flush()

    def do_GET(self):
        global REQUEST_COUNT

        if self.path == '/healthz':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')

        elif self.path == '/readyz':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'READY')

        elif self.path == '/metrics':
            REQUEST_COUNT += 1
            # Prometheus text exposition format
            metrics = (
                "# HELP http_requests_total Total HTTP requests processed.\n"
                "# TYPE http_requests_total counter\n"
                f'http_requests_total{{path="/metrics"}} {REQUEST_COUNT}\n'
            )
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            self.wfile.write(metrics.encode('utf-8'))

        elif self.path == '/api/quote':
            REQUEST_COUNT += 1
            # Simulate ~100ms of CPU work
            start_time = time.time()
            while (time.time() - start_time) < 0.1:
                _ = [i**2 for i in range(1000)]

            quote = random.choice(QUOTES)
            response_data = json.dumps({"quote": quote})

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(response_data.encode('utf-8'))

        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not Found')

def run(server_class=HTTPServer, handler_class=APIHandler, port=8080):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting server on port {port}...", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    print("Server stopped.", flush=True)

if __name__ == '__main__':
    run()