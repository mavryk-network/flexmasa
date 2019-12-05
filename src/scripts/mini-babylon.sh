#! /bin/sh

echo "Starting mini-babylon sandbox" >&2

flextesarl mini-net \
--root /tmp/mini-babylon --size 1 "$@" \
--number-of-b 1 \
--time-b 8 \
--until-level 2_000_000 \
--tezos-baker tezos-baker-005-PsBabyM1 \
--tezos-endor tezos-endorser-005-PsBabyM1 \
--tezos-accus tezos-accuser-005-PsBabyM1 \
--protocol-hash PsBabyM1eUXZseaJdmXFApDSBqj8YBfwELoxZHHW77EMcAbbwAS

