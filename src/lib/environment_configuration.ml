open! Internal_pervasives

(** Global configuration from environment variables and such. *)

type t = {prefix: string; disabled: bool}

let default () = {prefix= "flextesa_"; disabled= false}

type 'a state = < env_config: t ; .. > as 'a

let prefix state = state#env_config.prefix

let get_from_environment state varname =
  Fmt.kstr Sys.getenv_opt "%s%s" (prefix state) varname

let default_cors_origin state =
  match get_from_environment state "node_cors_origin" with
  | Some "" | None -> None
  | Some other -> Some other
