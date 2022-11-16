## Waku Message module
##
## See 14/WAKU-MESSAGE RFC: https://rfc.vac.dev/spec/14/
##
## For payload content and encryption, see waku/v2/node/waku_payload.nim

when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  ./waku_message/message

export
  message
