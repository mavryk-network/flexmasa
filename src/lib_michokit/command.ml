open Flextesa
open Internal_pervasives
module IFmt = Experiments.More_fmt

module Concrete = struct
  module Parse_error = struct
    type t = [`Michelson_parsing of string * exn]

    let pp ppf (`Michelson_parsing (code, ex)) =
      let open IFmt in
      wrapping_box ~indent:2 ppf (fun ppf ->
          pf ppf "Michelson-parsing-error:" ;
          sp ppf () ;
          long_string ppf code ;
          sp ppf () ;
          string ppf "->" ;
          sp ppf () ;
          exn ppf ex)

    let fail s e = fail (`Michelson_parsing (s, e))
  end

  let parse s =
    try
      Tezos_client_alpha.Michelson_v1_parser.(
        (parse_toplevel s |> fst).expanded)
      |> return
    with e -> Parse_error.fail s e

  let to_string e =
    let buf = Buffer.create 1000 in
    let fmt = Format.formatter_of_buffer buf in
    Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped fmt e ;
    Format.pp_print_flush fmt () ;
    Buffer.contents buf
end

module Tz_protocol = Tezos_protocol_alpha.Protocol

module Transform = struct
  let strip_errors_and_annotations expr =
    let open Tz_protocol.Environment.Micheline in
    let all_failwith_arguments = ref [] in
    let add_failwith_argument arg =
      match List.find !all_failwith_arguments ~f:(fun (_, a) -> a = arg) with
      | Some (id, _) ->
          (* Printf.eprintf "found %d\n%!" id ; *)
          id
      | None ->
          let id = List.length !all_failwith_arguments in
          all_failwith_arguments := (id, arg) :: !all_failwith_arguments ;
          (* Printf.eprintf "not found %d\n%!" id ; *)
          id in
    let rec transform = function
      | (Int _ | String _ | Bytes _) as e -> e
      | Prim (a, b, nl, _ann) -> Prim (a, b, List.map ~f:transform nl, [])
      | Seq (loc, node_list) ->
          let open Tz_protocol.Michelson_v1_primitives in
          let new_node_list =
            match node_list with
            | [ ( Prim
                    ( l1
                    , I_PUSH
                    , (* [Prim (l2, T_string, ns, _anns); String (l3, s)] *)
                    _
                    , _annt ) as anything )
              ; Prim (l4, I_FAILWITH, nf, _annf) ] ->
                (* Format.eprintf "\n\n\nFound failwith: %S\n%!" s ; *)
                let id = add_failwith_argument (strip_locations anything) in
                [ Prim
                    ( l1
                    , I_PUSH
                    , [ Prim (l1, T_nat, [], [])
                      ; Int (l1, Z.of_int id) (* Prim (l1, D_Unit, [], []) *)
                        (* ; Int (l1, Z.zero) *) ]
                    , [] )
                ; Prim (l4, I_FAILWITH, nf, []) ]
            | nl -> List.map ~f:transform nl in
          Seq (loc, new_node_list) in
    let res_node = transform (root expr) in
    (strip_locations res_node, !all_failwith_arguments)
end

module Json = struct
  let dummy_storage () =
    let open Tz_protocol.Environment.Micheline in
    Seq (0, []) |> strip_locations

  let of_expr expr =
    match
      Tezos_data_encoding.Data_encoding.Json.construct
        Tz_protocol.Script_repr.encoding
        Tz_protocol.Script_repr.
          {code= lazy_expr expr; storage= lazy_expr (dummy_storage ())}
    with
    | `O [("code", o); ("storage", _)] -> return (o : Ezjsonm.value)
    | _other -> System_error.fail "Error with expr->json: this is a bug"
end

let run ?output_error_codes state ~input_file ~output_file () =
  ( match Filename.extension input_file with
  | ".tz" ->
      System.read_file state input_file
      >>= fun content -> Concrete.parse content
  | other -> System_error.fail "Cannot parse file with extension %S" other )
  >>= fun expr ->
  let transformed, error_codes = Transform.strip_errors_and_annotations expr in
  ( match Filename.extension output_file with
  | ".tz" ->
      System.write_file state output_file
        ~content:(Concrete.to_string transformed)
  | ".json" ->
      Json.of_expr transformed
      >>= fun json ->
      System.write_file state output_file
        ~content:(Ezjsonm.value_to_string ~minify:false json)
  | other -> System_error.fail "Don't know what to do with extension %S" other
  )
  >>= fun () ->
  Asynchronous_result.map_option output_error_codes ~f:(fun path ->
      List.fold error_codes ~init:(return [])
        ~f:(fun prevm (code, error_msg) ->
          prevm
          >>= fun prevl ->
          Json.of_expr error_msg
          >>= fun json ->
          return (Ezjsonm.(dict [("code", int code); ("value", json)]) :: prevl))
      >>= fun jsons ->
      System.write_file state path
        ~content:(Ezjsonm.to_string ~minify:false (`A jsons))
      >>= fun () ->
      return
        IFmt.(
          fun ppf ->
            wf ppf "%d “error codes” output to `%s`."
              (List.length error_codes) path))
  >>= fun pp_opt ->
  Console.sayf state
    IFmt.(
      fun ppf () ->
        vertical_box ppf (fun ppf ->
            wf ppf "Convertion+stripping: `%s` -> `%s`." input_file output_file ;
            Option.iter pp_opt ~f:(fun f -> cut ppf () ; f ppf)) ;
        cut ppf () ;
        vertical_box ppf ~indent:4 (fun ppf ->
            wf ppf "Deserialized cost:" ;
            cut ppf () ;
            pf ppf "* From: %a" Tz_protocol.Gas_limit_repr.pp_cost
              (Tz_protocol.Script_repr.deserialized_cost expr) ;
            cut ppf () ;
            pf ppf "* To:   %a" Tz_protocol.Gas_limit_repr.pp_cost
              (Tz_protocol.Script_repr.deserialized_cost transformed)) ;
        cut ppf () ;
        wf ppf "Binary-Bytes: %d -> %d"
          (Tezos_data_encoding.Data_encoding.Binary.length
             Tz_protocol.Script_repr.expr_encoding expr)
          (Tezos_data_encoding.Data_encoding.Binary.length
             Tz_protocol.Script_repr.expr_encoding transformed))

let make ?(command_name = "michokit") () =
  let open Cmdliner in
  let open Term in
  let pp_error ppf e =
    match e with
    | `Lwt_exn _ as e -> Lwt_exception.pp ppf e
    | `Sys_error _ as e -> System_error.pp ppf e
    | `Michelson_parsing _ as mp -> Concrete.Parse_error.pp ppf mp in
  Test_command_line.Run_command.make ~pp_error
    ( pure (fun input_file output_file output_error_codes state ->
          (state, run state ~input_file ~output_file ?output_error_codes))
    $ Arg.(
        required
          (pos 0 (some string) None
             (info [] ~docv:"INPUT-PATH" ~doc:"Input file.")))
    $ Arg.(
        required
          (pos 1 (some string) None
             (info [] ~docv:"OUTPUT-PATH" ~doc:"Output file.")))
    $ Arg.(
        value
          (opt (some string) None
             (info ["output-error-codes"]
                ~doc:"Output the matching of error values to integers.")))
    $ Test_command_line.cli_state ~name:command_name () )
    (info command_name ~doc:"CLI for Flextesa_extras.Michokit")
