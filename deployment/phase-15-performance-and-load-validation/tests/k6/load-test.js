import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "2m", target: 20 },
    { duration: "5m", target: 20 },
    { duration: "2m", target: 0 }
  ],
  thresholds: {
    http_req_failed: ["rate<0.02"],
    http_req_duration: ["p(95)<800", "p(99)<1500"]
  }
};

const baseUrl = __ENV.BASE_URL || "http://localhost";

export default function () {
  const responses = http.batch([
    ["GET", `${baseUrl}/`],
    ["GET", `${baseUrl}/health`],
    ["GET", `${baseUrl}/ready`]
  ]);

  check(responses[0], {
    "frontend is successful": (response) => response.status === 200
  });

  check(responses[1], {
    "health is successful": (response) => response.status === 200
  });

  check(responses[2], {
    "ready is successful": (response) => response.status === 200
  });

  sleep(1);
}
