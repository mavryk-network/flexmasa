open Internal_pervasives

type t =
  { level: int
  ; name: string
  ; node: Tezos_executable.t
  ; client: Tezos_executable.t }

val originate :
     < application_name: string
     ; console: Console.t
     ; env_config: Environment_configuration.t
     ; paths: Paths.t
     ; runner: Running_processes.State.t
     ; .. >
  -> string
  -> Tezos_client.t
  -> string
  -> ( < err: string list ; out: string list ; status: Unix.process_status >
     , [> `Process_error of Process_result.Error.error
       | `System_error of [`Fatal] * System_error.static ] )
     Asynchronous_result.t
(** [orginate state name client acc ] is a tezos [client] call to orginate a Transactional Rollup
     from account [acc]. The rollup will be geven the [name] provieded *)

val executables : t -> Tezos_executable.t list
(** List of executables for the Transactional Rollup *)

val cmdliner_term :
     < manpager: Manpage_builder.State.t ; .. >
  -> docs:string
  -> unit
  -> t option Cmdliner.Term.t
(** Command line option which starts a transactional rollup and with the rollup node and client. *)
