import { onSchedule } from "firebase-functions/v2/scheduler";
import { runPollFlights } from "../store/flights";
import { dataGoKrServiceKey } from "../store/providerGateway";
import { REGION } from "../callable/common";

export const pollFlights = onSchedule(
  {
    schedule: "every 15 minutes",
    region: REGION,
    timeZone: "Asia/Tokyo",
    timeoutSeconds: 300,
    secrets: [dataGoKrServiceKey],
  },
  async (event) => {
    const parsed = new Date(event.scheduleTime);
    const now = Number.isNaN(parsed.getTime()) ? new Date() : parsed;
    const events = await runPollFlights(now, dataGoKrServiceKey.value());
    // M6: 변경 알림 발송
    void events;
  },
);
