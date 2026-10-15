import { searchFlightFor } from "../store/flights";
import { dataGoKrServiceKey } from "../store/providerGateway";
import { onAuthenticatedCall } from "./common";

export const searchFlight = onAuthenticatedCall(
  async (uid, data) => searchFlightFor(uid, data, dataGoKrServiceKey.value()),
  { secrets: [dataGoKrServiceKey] },
);
