import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 1,
  duration: "30s",
  thresholds: {
    checks: ["rate>0.99"],
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const frontend = http.get(`${baseUrl}/`);
  const health = http.get(`${baseUrl}/health`);
  const ready = http.get(`${baseUrl}/ready`);

  check(frontend, {
    "frontend is available": (response) => response.status === 200
  });

  check(health, {
    "health endpoint is available": (response) => response.status === 200
  });

  check(ready, {
    "ready endpoint is available": (response) => response.status === 200
  });

  sleep(1);
}
