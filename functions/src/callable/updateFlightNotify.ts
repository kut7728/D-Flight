import { parseUpdateFlightNotify } from "../domain/validate";
import { updateFlightNotify as saveNotify } from "../store/users";
import { onAuthenticatedCall } from "./common";

export const updateFlightNotify = onAuthenticatedCall(async (uid, data) => {
  const input = parseUpdateFlightNotify(data);
  await saveNotify(uid, input.trackedId, input.notify);
  return {};
});
