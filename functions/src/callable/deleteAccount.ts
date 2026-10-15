import { parseDeleteAccount } from "../domain/validate";
import { deleteAccountData } from "../store/account";
import { onAuthenticatedCall } from "./common";

export const deleteAccount = onAuthenticatedCall(async (uid, data) => {
  parseDeleteAccount(data);
  await deleteAccountData(uid);
  return {};
});
