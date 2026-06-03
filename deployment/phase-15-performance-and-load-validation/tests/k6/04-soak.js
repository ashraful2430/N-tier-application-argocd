import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "5m", target: 20 },
    { duration: "45m", target: 20 },
    { duration: "5m", target: 0 }
  ],
  thresholds: {
    checks: ["rate>0.98"],
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<1000"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const health = http.get(`${baseUrl}/health`);
  const ready = http.get(`${baseUrl}/ready`);

  check(health, {
    "health remains good": (result) => result.status === 200
  });

  check(ready, {
    "readiness remains good": (result) => result.status === 200
  });

  sleep(2);
}
