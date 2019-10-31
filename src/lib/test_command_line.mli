(** Functions for building test-scenarios commands. *)

open Internal_pervasives

(** Make {!Cmdliner} commands from {!Asynchronous_result} functions. *)
module Run_command : sig
  module Common_errors : sig
    type t =
      [ `Die of int
      | `Empty_protocol_list
      | `Precheck_failure of string
      | Process_result.Error.t
      | `Scenario_error of string
      | System_error.t
      | Test_scenario.Inconsistency_error.t
      | `Waiting_for of string * [`Time_out] ]

    val pp : Format.formatter -> t -> unit
  end

  val make :
       pp_error:(Format.formatter -> ([> ] as 'errors) -> unit)
    -> ( < application_name: string ; console: Console.t ; .. >
       * (unit -> (unit, 'errors) Asynchronous_result.t) )
       Cmdliner.Term.t
    -> Cmdliner.Term.info
    -> unit Cmdliner.Term.t * Cmdliner.Term.info
end

val cli_state :
     ?default_interactivity:Interactive_test.Interactivity.t
  -> ?disable_interactivity:bool
  -> name:string
  -> unit
  -> < application_name: string
     ; env_config: Environment_configuration.t
     ; console: Console.t
     ; operations_log: Log_recorder.Operations.t
     ; paths: Paths.t
     ; pauser: Interactive_test.Pauser.t
     ; runner: Running_processes.State.t
     ; test_interactivity: Interactive_test.Interactivity.t >
     Cmdliner.Term.t
(** Create a full [state] value for test-scenarios. *)
