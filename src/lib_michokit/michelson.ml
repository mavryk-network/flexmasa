open Flextesa
open Internal_pervasives
module IFmt = More_fmt

module Concrete = struct
  module Parse_error = struct
    type t =
      [ `Michelson_parsing of
        string
        * [`Exn of exn | `Tz_errors of Tezos_error_monad.Error_monad.error list]
      ]

    let pp ppf (`Michelson_parsing (code, ex)) =
      let open IFmt in
      wrapping_box ~indent:2 ppf (fun ppf ->
          pf ppf "Michelson-parsing-error:" ;
          sp ppf () ;
          long_string ppf code ;
          sp ppf () ;
          string ppf "->" ;
          sp ppf () ;
          match ex with
          | `Exn e -> exn ppf e
          | `Tz_errors l -> Tezos_error_monad.Error_monad.pp_print_error ppf l)

    let fail s e = fail (`Michelson_parsing (s, e) : [> t])
  end

  let parse s =
    try
      Tezos_client_alpha.Michelson_v1_parser.(
        let parsed, errors = parse_toplevel ~check:true s in
        match errors with
        | [] -> return parsed.expanded
        | more -> Parse_error.fail s (`Tz_errors more))
    with e -> Parse_error.fail s (`Exn e)

  let to_string e =
    let buf = Buffer.create 1000 in
    let fmt = Caml.Format.formatter_of_buffer buf in
    Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped fmt e ;
    Caml.Format.pp_print_flush fmt () ;
    Buffer.contents buf
end

module Tz_protocol = Tezos_protocol_alpha.Protocol

module Transform = struct
  module On_annotations = struct
    type t = [`Keep | `Strip | `Replace of (string * string) list]

    let perform (t : t) l =
      match t with
      | `Keep -> l
      | `Replace replacements ->
          List.map l ~f:(fun ann ->
              match
                List.find replacements ~f:(fun (k, _) -> String.equal ann k)
              with
              | None -> ann
              | Some (_, v) -> v)
      | `Strip -> []

    let cmdliner_term () : t Cmdliner.Term.t =
      let open Cmdliner in
      let open Term in
      term_result
        ( const (fun keep strip replace ->
              match (keep, strip, replace) with
              | _, false, None -> Ok `Keep
              | false, true, None -> Ok `Strip
              | false, false, Some l -> Ok (`Replace l)
              | _, _, _ ->
                  Error
                    (`Msg
                      "Annotations (--*-annotations) options should be \
                       mutually exclusive."))
        $ Arg.(
            value
              (flag
                 (info ["keep-annotations"]
                    ~doc:"Keep annotations (the default).")))
        $ Arg.(
            value
              (flag (info ["strip-annotations"] ~doc:"Remove all annotations.")))
        $ Arg.(
            value
              (opt
                 (some (list ~sep:',' (pair ~sep:':' string string)))
                 None
                 (info ["replace-annotations"]
                    ~doc:"Perform replacement on annotations."))) )
  end

  let strip_errors ?(on_annotations = `Keep) expr =
    let open Tz_protocol.Environment.Micheline in
    let all_failwith_arguments = ref [] in
    let add_failwith_argument arg =
      match
        List.find !all_failwith_arguments ~f:(fun (_, a) -> Poly.equal a arg)
      with
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
      | Prim (a, b, nl, ann) ->
          Prim
            ( a
            , b
            , List.map ~f:transform nl
            , On_annotations.perform on_annotations ann )
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
                (* Caml.Format.eprintf "\n\n\nFound failwith: %S\n%!" s ; *)
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
      Data_encoding.Json.construct Tz_protocol.Script_repr.encoding
        Tz_protocol.Script_repr.
          {code= lazy_expr expr; storage= lazy_expr (dummy_storage ())}
    with
    | `O [("code", o); ("storage", _)] -> return (o : Ezjsonm.value)
    | _other -> System_error.fail_fatalf "Error with expr->json: this is a bug"
end

module File_io = struct
  let read_file state input_file :
      ( Tezos_protocol_alpha.Protocol.Alpha_context.Script.expr
      , [> Concrete.Parse_error.t | Flextesa.Internal_pervasives.System_error.t]
      )
      Flextesa.Internal_pervasives.Attached_result.t
      Lwt.t =
    match Caml.Filename.extension input_file with
    | ".tz" ->
        System.read_file state input_file
        >>= fun content -> Concrete.parse content
    | other ->
        System_error.fail_fatalf "Cannot parse file with extension %S" other

  let write_file state ~path expr =
    match Caml.Filename.extension path with
    | ".tz" -> System.write_file state path ~content:(Concrete.to_string expr)
    | ".json" ->
        Json.of_expr expr
        >>= fun json ->
        System.write_file state path
          ~content:(Ezjsonm.value_to_string ~minify:false json)
    | other ->
        System_error.fail_fatalf "Don't know what to do with extension %S"
          other
end

module Typed_ir = struct
  let of_tz_error_monad pp_error f =
    let open Lwt in
    f ()
    >>= function
    | Ok o -> Asynchronous_result.return o
    | Error el ->
        System_error.fail_fatalf "Tz-Error: %a" Fmt.(list ~sep:sp pp_error) el

  let pp_tz_error = Tezos_error_monad.Error_monad.pp

  let pp_protocol_error =
    Tezos_protocol_environment_alpha.Environment.Error_monad.pp

  let make_fresh_context () =
    of_tz_error_monad pp_tz_error (fun () ->
        Tezos_client_alpha.Mockup.mem_init
          Tezos_client_alpha.Mockup.default_mockup_parameters)
    >>= fun {context; _} ->
    of_tz_error_monad pp_protocol_error (fun () ->
        Tezos_raw_protocol_alpha.Alpha_context.prepare context ~level:1l
          ~predecessor_timestamp:
            Tezos_protocol_environment_alpha.Environment.Time.(of_seconds 1L)
          ~timestamp:
            Tezos_protocol_environment_alpha.Environment.Time.(of_seconds 2L)
          ~fitness:(* Tezos_raw_protocol_alpha.Alpha_context.Fitness. *) [])

  let parse_type node =
    make_fresh_context ()
    >>= fun context ->
    match
      Tz_protocol.Script_ir_translator.parse_ty context ~legacy:false
        ~allow_big_map:true ~allow_operation:true ~allow_contract:true node
    with
    | Ok (ex_ty, _context) -> return ex_ty
    | Error el ->
        System_error.fail_fatalf "Error parsing the type: %a\n%!"
          Fmt.(
            list ~sep:sp
              Tezos_protocol_environment_alpha.Environment.Error_monad.pp)
          el

  let unparse_type = function
    | Tezos_raw_protocol_alpha.Script_ir_translator.Ex_ty ty ->
        make_fresh_context ()
        >>= fun context ->
        of_tz_error_monad pp_protocol_error (fun () ->
            Tz_protocol.Script_ir_translator.unparse_ty context ty)
        >>= fun (node, _context) -> return node
end
