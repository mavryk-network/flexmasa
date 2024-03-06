(lang dune 2.8)
(name flexmasa)
(generate_opam_files true)
(license MIT)
(source (uri git+https://gitlab.com/mavryk-network/flexmasa.git))
(homepage https://gitlab.com/mavryk-network/flexmasa)
(bug_reports https://gitlab.com/mavryk-network/flexmasa)
(authors "Seb Mondet <seb@mondet.org>" "Mark Nichols")
(maintainers "seb@mondet.org")

(package
 (name mavai-mv1-crypto)
 (synopsis "Tezos Ed25519 Accounts Based on Mirage-Crypto")
 (description "Tezos Ed25519 Accounts Based on Mirage-Crypto.")
 (version 0.2)
 (depends
   "mavai-base58-digest"
  (mirage-crypto (>= "0.11.0"))
  (dune (>= "2.9"))
  (ppx_inline_test ( >= "0.14.0"))
  (ppx_expect (>= "0.14.0"))
 )
)

(package
 (name flexmasa)
 (synopsis "Flexible Tezos Sandboxes: A library to define sandboxed Tezos networks")
 (description "Flexible Tezos Sandboxes: A library to define sandboxed Tezos networks.")
 (depends
  (dune (> 2.8))
  ("genspio" (= "0.0.2"))
  base
  fmt
  ppx_sexp_conv
  ezjsonm
  dum
  cmdliner
  tls
  cohttp-lwt-unix
  (pp (>= 1.1.2))
  mavai-base58-digest
  mavai-mv1-crypto
  ))

(package
 (name flexmasa-cli)
 (synopsis "A CLI application using Flexmasa-lib to define a few scenarios")
 (description "A CLI application using Flexmasa-lib to define a few scenarios.")
 (depends
  (dune (> 2.8))
  flexmasa
  )
  )
