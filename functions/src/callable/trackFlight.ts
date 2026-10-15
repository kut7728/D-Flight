import { trackFlightFor } from "../store/flights";
import { onAuthenticatedCall } from "./common";

export const trackFlight = onAuthenticatedCall(async (uid, data) => trackFlightFor(uid, data));
