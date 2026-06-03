import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "5m", target: 15 },
    { duration: "30m", target: 15 },
    { duration: "5m", target: 0 }
  ],
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<1000"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const response = http.get(`${baseUrl}/health`);

  check(response, {
    "health endpoint stays healthy": (result) => result.status === 200
  });

  sleep(2);
}
