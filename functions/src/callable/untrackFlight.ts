import { untrackFlightFor } from "../store/flights";
import { onAuthenticatedCall } from "./common";

export const untrackFlight = onAuthenticatedCall(async (uid, data) => untrackFlightFor(uid, data));
