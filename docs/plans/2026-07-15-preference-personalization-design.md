# Preference-driven recommendations and narrative tone

LumaNest personalizes only creative events that deterministic context rules
have already established. Local profile preferences may change their order and
the tone used to rewrite their copy, but never create facts, change actions,
alter expiry, or hide safety events.

The client converts persisted photography and activity selections into a
small typed `CreativePersonalization`. Recommendation strength has three
deterministic bands: preserve order, move a match by at most one position, and
stable preference-first ordering. Today, Inspiration, and Narrative consume
the same resulting manifest.

The personalization fingerprint contains only sorted preference enum names,
narrative tone, and the normalized recommendation strength. Equipment,
accessibility, device, location, and identity data are excluded. Only the tone
enum is sent to the Broker. Missing tone remains compatible with older clients
and defaults to balanced. Model output remains constrained to existing
creative event IDs and the existing response schema.
