import { parseSettings } from "../domain/validate";
import { mergeSettings } from "../store/users";
import { onAuthenticatedCall } from "./common";

export const updateSettings = onAuthenticatedCall(async (uid, data) => {
  await mergeSettings(uid, parseSettings(data));
  return {};
});
