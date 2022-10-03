open Internal_pervasives

module Account = struct
  type t =
    {name: string; operation_hash: string; address: string; out: string list}

  let make ~name ~operation_hash ~address ~out : t =
    {name; operation_hash; address; out}

  (*  TODO this is wonky but it works. Maybe there is a better way.*)
  let parse_origination ~lines =
    let rec prefix_from_list ~prefix = function
      | [] -> None
      | x :: xs ->
          if not (String.is_prefix x ~prefix) then prefix_from_list ~prefix xs
          else
            Some
              (String.lstrip
                 (String.chop_prefix x ~prefix |> Option.value ~default:x) )
    in
    let l = List.map lines ~f:String.lstrip in
    Option.(
      prefix_from_list ~prefix:"Operation hash is" l
      >>= fun op ->
      String.chop_prefix ~prefix:"'" op
      >>= fun suf ->
      String.chop_suffix ~suffix:"'" suf
      >>= fun operation_hash ->
      prefix_from_list ~prefix:"Originated tx rollup:" l
      >>= fun address ->
      prefix_from_list ~prefix:"Transaction rollup memorized as" l
      >>= fun name -> return (make ~name ~operation_hash ~address ~out:lines))

  let originate state ~name ~client ~acc =
    Tezos_client.successful_client_cmd state ~client
      ["originate"; "tx"; "rollup"; name; "from"; acc; "--burn-cap"; "15"]

  let confirm state ~client ?(confirmations = 0) ~operation_hash () =
    Tezos_client.successful_client_cmd state ~client
      [ "wait"; "for"; operation_hash; "to"; "be"; "included"; "--confirmations"
      ; Int.to_string confirmations ]

  let originate_and_confirm state ~name ~client ~acc ?confirmations () =
    originate state ~name ~client ~acc
    >>= fun res ->
    return (parse_origination ~lines:res#out)
    >>= fun rollup ->
    match rollup with
    | None ->
        System_error.fail_fatalf
          "Tx_rollup.originate_and_confirm - failed to parse rollup."
    | Some acc ->
        confirm state ~client ?confirmations ~operation_hash:acc.operation_hash
          ()
        >>= fun conf -> return (acc, conf#out)
end

module Tx_node = struct
  type mode = Observer | Accuser | Batcher | Maintenance | Operator | Custom

  type t =
    { id: string
    ; port: int option
    ; endpoint: int
    ; protocol: Tezos_protocol.Protocol_kind.t
    ; exec: Tezos_executable.t
    ; client: Tezos_client.t
    ; mode: mode
    ; cors_origin: string option
    ; account: Account.t
    ; operation_signers: string list }

  let make_path p ~config t =
    Paths.root config // sprintf "tx-rollup-%s" t.id // p

  let data_dir config t = make_path "data-dir" ~config t
  let exec_path config t = make_path "exec" ~config t

  open Tezos_executable.Make_cli

  let mode_string = function
    | Observer -> "observer"
    | Accuser -> "accuser"
    | Batcher -> "batcher"
    | Maintenance -> "maintenance"
    | Operator -> "operator"
    | Custom -> "custom "

  let signers ~operator ~batcher ?finalize_commitment ?remove_commitment
      ?rejection ?dispatch_withdrawals () =
    let or_op_key = function None -> operator | Some k -> k in
    opt "operator" operator @ opt "batch-signer" batcher
    @ opt "finalize-commitment-signer" (or_op_key finalize_commitment)
    @ opt "remove-commitment-signer" (or_op_key remove_commitment)
    @ opt "rejection-signer" (or_op_key rejection)
    @ opt "dispatch-withdrawals-signer" (or_op_key dispatch_withdrawals)

  let make ?id ?port ~endpoint ~protocol ~exec ~client ~mode ?cors_origin
      ~account ~operation_signers () =
    { id=
        (fun s ->
          sprintf "%s-%s-node-%s" account.Account.name (mode_string mode)
            (Option.value s ~default:"000") )
          id
    ; port
    ; endpoint
    ; protocol
    ; exec
    ; client
    ; mode
    ; cors_origin
    ; account
    ; operation_signers }

  let call state t command =
    let client_dir = Tezos_client.base_dir ~state t.client in
    let cors_origin =
      match t.cors_origin with
      | Some _ as s -> s
      | None -> Environment_configuration.default_cors_origin state in
    Tezos_executable.call state t.exec ~protocol_kind:t.protocol
      ~path:(exec_path state t // sprintf "exec-toru-%s" t.id)
      (* TODO try:  t.node.Tezos_node.rpc_port *)
      ( opt "endpoint" (sprintf "http://localhost:%d" t.endpoint)
      @ opt "base-dir" client_dir
      (* @ opt "config-file" (config_file state t) *)
      @ command
      @ opt "data-dir" (data_dir state t)
      @ Option.value_map cors_origin
          ~f:(fun s ->
            flag "cors-header=content-type" @ Fmt.kstr flag "cors-origin=%s" s
            )
          ~default:[]
      @ flag "allow-deposit" @ t.operation_signers )

  let init state t =
    call state t
      ( ["init"; mode_string t.mode; "config"; "for"; t.account.address]
      @ flag "force" )

  let run state t =
    call state t ["run"; mode_string t.mode; "for"; t.account.address]

  let start_script state t =
    let open Genspio.EDSL in
    check_sequence ~verbosity:`Output_all
      [("init node", init state t); ("run node", run state t)]

  let process state t script =
    Running_processes.Process.genspio
      (sprintf "%s-node-for-tx-rollup-%s" (mode_string t.mode) t.account.name)
      (script state t)

  (* TODO Maybe add signer key options too? *)

  let cmdliner_term state ~extra_doc =
    let open Cmdliner in
    let open Term in
    let docs =
      Manpage_builder.section state ~rank:2 ~name:"TRANSACTIONAL ROLLUP NODE"
    in
    const (fun mode ->
        match mode with
        | "observer" -> Observer
        | "accuser" -> Accuser
        | "batcher" -> Batcher
        | "maintenance" -> Maintenance
        | "custom " -> Custom
        | "operator" | _ -> Operator )
    $ Arg.(
        value
          (opt string "operator"
             (info ~docs ["tx-rollup-node-mode"]
                ~doc:
                  (sprintf
                     "Set the rollup node's `mode` %s. Possible modes include: \
                      operator, observer, accuser, batcher, maintenance and \
                      custom."
                     extra_doc ) ) ))
end

type t =
  { level: int
  ; name: string
  ; node: Tezos_executable.t
  ; client: Tezos_executable.t
  ; mode: Tx_node.mode }

let executables ({client; node; _} : t) = [client; node]

(* TODO
   add option for conformations required
   add option for mode
*)
let cmdliner_term base_state ~docs () =
  let open Cmdliner in
  let open Term in
  let extra_doc = Fmt.str " for transactional rollups (requires --tx-rollup)" in
  const (fun tx_rollup node client mode ->
      Option.map tx_rollup ~f:(fun (level, name) ->
          let txr_name =
            match name with None -> "flextesa-tx-rollup" | Some n -> n in
          {level; name= txr_name; node; client; mode} ) )
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
  $ Tx_node.cmdliner_term ~extra_doc base_state
