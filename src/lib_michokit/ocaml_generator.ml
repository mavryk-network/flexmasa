open Flextesa
open Internal_pervasives
module IFmt = More_fmt

let make_module expr =
  let open Michelson.Tz_protocol.Environment.Micheline in
  let module Prim = Michelson.Tz_protocol.Michelson_v1_primitives in
  match root expr with
  | Seq (_, Prim (_, Prim.K_parameter, [the_type], _ann) :: _) ->
      Michelson.Typed_ir.parse_type the_type
      >>= fun ex_ty ->
      Michelson.Typed_ir.unparse_type ex_ty
      >>= fun back_to_node ->
      (* Dbg.f (fun f -> f "Found the type: %a" Dbg.pp_any the_type) ; *)
      let first_comment =
        Fmt.str "(* Generated code for\n%a\n*)\n"
          Tezos_client_alpha.Michelson_v1_printer.print_expr_unwrapped
          (strip_locations back_to_node) in
      (* Dbg.f (fun f -> f "Built the type: %a" Dbg.pp_any ty) ; *)
      return first_comment
  | _ -> Fmt.failwith "not here"

module Command = struct
  let run state ~input_file ~output_file () =
    let open Michelson in
    File_io.read_file state input_file
    >>= fun expr ->
    make_module expr
    >>= fun ocaml -> System.write_file state output_file ~content:ocaml

  let make ?(command_name = "ocaml-of-michelson") () =
    let open Cmdliner in
    let open Term in
    let pp_error ppf e =
      match e with
      | #System_error.t as e -> System_error.pp ppf e
      | `Michelson_parsing _ as mp -> Michelson.Concrete.Parse_error.pp ppf mp
    in
    Test_command_line.Run_command.make ~pp_error
      ( pure (fun input_file output_file state ->
            (state, run state ~input_file ~output_file))
      $ Arg.(
          required
            (pos 0 (some string) None
               (info [] ~docv:"INPUT-PATH" ~doc:"Input file.")))
      $ Arg.(
          required
            (pos 1 (some string) None
               (info [] ~docv:"OUTPUT-PATH" ~doc:"Output file.")))
      $ Test_command_line.cli_state ~name:"michokit-ocofmi" () )
      (info command_name ~doc:"Generate OCaml code from Michelson.")
end
