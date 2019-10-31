open Internal_pervasives

module Run_command = struct
  module Common_errors = struct
    type t =
      [ `Die of int
      | `Empty_protocol_list
      | `Precheck_failure of string
      | Process_result.Error.t
      | `Scenario_error of string
      | System_error.t
      | Test_scenario.Inconsistency_error.t
      | `Waiting_for of string * [`Time_out] ]

    let pp ppf (e : t) =
      match e with
      | `Scenario_error s -> Format.fprintf ppf "%s" s
      | #Test_scenario.Inconsistency_error.t as e ->
          Format.fprintf ppf "%a" Test_scenario.Inconsistency_error.pp e
      | #Process_result.Error.t as e ->
          Format.fprintf ppf "%a" Process_result.Error.pp e
      | #System_error.t as e -> Format.fprintf ppf "%a" System_error.pp e
      | `Waiting_for (msg, `Time_out) ->
          Format.fprintf ppf "WAITING-FOR “%s”: Time-out" msg
      | `Precheck_failure _ as p -> Helpers.System_dependencies.Error.pp ppf p
      | `Die n -> Format.fprintf ppf "Exiting with %d" n
  end

  let or_hard_fail state main ~pp_error : unit =
    let open Asynchronous_result in
    Dbg.e EF.(wf "Run_command.or_hard_fail") ;
    run_application (fun () ->
        Dbg.e EF.(wf "Run_command.or_hard_fail bind_on_error") ;
        bind_on_error (main ()) ~f:(fun ~result _ ->
            Dbg.e EF.(wf "Run_command.or_hard_fail on result") ;
            transform_error
              ~f:(fun _ -> `Die 3)
              (Console.say state
                 EF.(
                   custom (fun ppf -> Attached_result.pp ppf result ~pp_error)))
            >>= fun () -> die 2)
        >>= fun () ->
        Dbg.e EF.(wf "Run_command.or_hard_fail after bind_on_error") ;
        return ())

  let term ~pp_error () =
    Cmdliner.Term.pure (fun (state, run) -> or_hard_fail state run ~pp_error)

  let make ~pp_error t (i : Cmdliner.Term.info) =
    Cmdliner.Term.(term ~pp_error () $ t, i)
end

let cli_state ?default_interactivity ?(disable_interactivity = false) ~name ()
    =
  let runner = Running_processes.State.make () in
  let default_root = sprintf "/tmp/%s-test" name in
  let app = sprintf "Flextesa.%s" name in
  let pauser = Interactive_test.Pauser.make [] in
  let ops = Log_recorder.Operations.make () in
  let env_config = Environment_configuration.default () in
  let state console paths interactivity =
    object
      method paths = paths

      method runner = runner

      method console = console

      method application_name = app

      method test_interactivity = interactivity

      method pauser = pauser

      method operations_log = ops

      method env_config = env_config
    end in
  let open Cmdliner in
  Term.(
    pure state $ Console.cli_term ()
    $ Paths.cli_term ~default_root ()
    $
    if disable_interactivity then pure `None
    else
      Interactive_test.Interactivity.cli_term ?default:default_interactivity ())
