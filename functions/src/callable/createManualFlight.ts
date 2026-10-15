import { createManualFlightFor } from "../store/flights";
import { onAuthenticatedCall } from "./common";

export const createManualFlight = onAuthenticatedCall(async (uid, data) => createManualFlightFor(uid, data));
