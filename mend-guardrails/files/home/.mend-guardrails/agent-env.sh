# Sourced by login/interactive shells. Do not set HTTP(S)_PROXY here.
_mend_guardrails_append_noproxy() {
  _var=$1
  eval "_val=\${${_var}:-}"
  case ",${_val}," in
    *,api.openai.com,*) ;;
    *)
      if [ -n "${_val}" ]; then
        export "${_var}=${_val},api.openai.com"
      else
        export "${_var}=api.openai.com"
      fi
      ;;
  esac
  unset _var _val
}

_mend_guardrails_append_noproxy NO_PROXY
_mend_guardrails_append_noproxy no_proxy
