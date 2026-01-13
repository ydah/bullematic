# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature "sig/generated"
  signature "sig/stubs"

  check "lib"

  configure_code_diagnostics do |hash|
    hash[D::Ruby::UnannotatedEmptyCollection] = :hint
    hash[D::Ruby::BlockTypeMismatch] = :hint
  end
end
