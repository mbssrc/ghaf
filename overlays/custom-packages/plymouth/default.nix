# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ prev }:
prev.plymouth.overrideAttrs {
  patches = (prev.plymouth.patches or [ ]) ++ [
    ./0001-fix-null-keyboard-handler-list-crash.patch
  ];
}
