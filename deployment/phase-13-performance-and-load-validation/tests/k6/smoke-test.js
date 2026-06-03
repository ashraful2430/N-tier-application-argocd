import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 1,
  duration: "30s",
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const frontend = http.get(`${baseUrl}/`);
  check(frontend, {
    "frontend returns 200": (response) => response.status === 200
  });

  const health = http.get(`${baseUrl}/health`);
  check(health, {
    "backend health returns 200": (response) => response.status === 200
  });

  const ready = http.get(`${baseUrl}/ready`);
  check(ready, {
    "backend ready returns 200": (response) => response.status === 200
  });

  sleep(1);
}
