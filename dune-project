(lang dune 2.8)
(name mavbox)
(generate_opam_files true)
(license MIT)
(source (uri git+https://gitlab.com/mavryk-network/mavbox.git))
(homepage https://gitlab.com/mavryk-network/mavbox)
(bug_reports https://gitlab.com/mavryk-network/mavbox)
(authors "Seb Mondet <seb@mondet.org>" "Mark Nichols" "Tristan Allaire <tristan@mavryk.io>")
(maintainers "seb@mondet.org" "tristan@mavryk.io")

(package
 (name mavryk-mv1-crypto)
 (synopsis "Mavryk Ed25519 Accounts Based on Mirage-Crypto")
 (description "Mavryk Ed25519 Accounts Based on Mirage-Crypto.")
 (version 0.2)
 (depends
   "mavryk-base58-digest"
  (mirage-crypto (>= "0.11.0"))
  (dune (>= "2.9"))
  (ppx_inline_test ( >= "0.14.0"))
  (ppx_expect (>= "0.14.0"))
 )
)

(package
 (name mavbox)
 (synopsis "Mavryk Sandboxes: A library to define sandboxed Mavryk networks")
 (description "Mavryk Sandboxes: A library to define sandboxed Mavryk networks.")
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
  mavryk-base58-digest
  mavryk-mv1-crypto
  ))

(package
 (name mavbox-cli)
 (synopsis "A CLI application using Mavbox-lib to define a few scenarios")
 (description "A CLI application using Mavbox-lib to define a few scenarios.")
 (depends
  (dune (> 2.8))
  mavbox
  )
  )
