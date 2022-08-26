open Internal_pervasives

type t =
  { level: int
  ; name: string
  ; node: Tezos_executable.t
  ; client: Tezos_executable.t }

let originate state name client acc =
  Tezos_client.successful_client_cmd state ~client
    ["originate"; "tx"; "rollup"; name; "from"; acc; "--burn-cap"; "15"]

let executables ({client; node; _} : t) = [client; node]

let cmdliner_term base_state ~docs () =
  let open Cmdliner in
  let open Cmdliner.Term in
  let extra_doc =
    Fmt.str " for the transactional rollups (requires --tx-rollup)" in
  const (fun tx_rollup node client ->
      Option.map tx_rollup ~f:(fun (level, name) ->
          let txr_name =
            match name with None -> "flextesa-tx-rollup" | Some n -> n in
          {level; name= txr_name; node; client} ) )
  $ Arg.(
      value
        (opt
           (some (t2 ~sep:':' int (some string)))
           None
           (info ["tx-rollup"]
              ~doc:"Orginate a transactional rollup `name` at `level`." ~docs
              ~docv:"LEVEL:TX-ROLLUP-NAME" ) ))
  $ Tezos_executable.cli_term ~extra_doc base_state `Tx_rollup_node "tezos"
  $ Tezos_executable.cli_term ~extra_doc base_state `Tx_rollup_client "tezos"
