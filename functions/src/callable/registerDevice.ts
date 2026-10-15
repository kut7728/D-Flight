import { parseRegisterDevice } from "../domain/validate";
import { registerDevice as saveDevice } from "../store/users";
import { onAuthenticatedCall } from "./common";

export const registerDevice = onAuthenticatedCall(async (uid, data) => {
  await saveDevice(uid, parseRegisterDevice(data));
  return {};
});
