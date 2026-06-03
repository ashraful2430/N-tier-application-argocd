import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "2m", target: 25 },
    { duration: "2m", target: 50 },
    { duration: "2m", target: 75 },
    { duration: "2m", target: 100 },
    { duration: "3m", target: 100 },
    { duration: "2m", target: 0 }
  ],
  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<2000"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const response = http.get(`${baseUrl}/ready`);

  check(response, {
    "ready endpoint responds": (result) => result.status === 200
  });

  sleep(1);
}
