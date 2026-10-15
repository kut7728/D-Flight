import { onSchedule } from "firebase-functions/v2/scheduler";
import { REGION } from "../callable/common";
import { runDailyCleanup } from "../store/flights";

export const dailyCleanup = onSchedule(
  {
    schedule: "0 4 * * *",
    region: REGION,
    timeZone: "Asia/Tokyo",
    timeoutSeconds: 300,
  },
  async (event) => {
    const parsed = new Date(event.scheduleTime);
    const now = Number.isNaN(parsed.getTime()) ? new Date() : parsed;
    await runDailyCleanup(now);
  },
);
