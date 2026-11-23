/* Where each piece of window.S and data.S sits in the address space of the running program.
   Used only at build time (build-assets/mkpages.py) to assemble the pieces for their run addresses. */
SECTIONS {
  .data2_array     0x3fdc2ed000 : { *(.data2_array) }
  .data2_table     0x3fdc2ee000 : { *(.data2_table) }
  .data2_stack     0x3feb846000 : { *(.data2_stack) }
  .data2_object    0x3feb849000 : { *(.data2_object) }
  .r_3ff2ee276e    0x3ff2ee276e : { *(.r_3ff2ee276e) }
  .r_199b0         0x3ff30199b0 : { *(.r_199b0) }
  .r_1ffe0         0x3ff301ffe0 : { *(.r_1ffe0) }
  .front           0x3ff5a1f000 : { *(.front) }
  .r_2a735b6       0x3ff5a735b6 : { *(.r_2a735b6) }
  .r_2a897b8       0x3ff5a897b8 : { *(.r_2a897b8) }
  .r_2a940dc       0x3ff5a940dc : { *(.r_2a940dc) }
  .r_2a9894c       0x3ff5a9894c : { *(.r_2a9894c) }
  .r_2aae580       0x3ff5aae580 : { *(.r_2aae580) }
  .r_2adff46       0x3ff5adff46 : { *(.r_2adff46) }
  .r_2aec63a       0x3ff5aec63a : { *(.r_2aec63a) }
  .g_4ea9718       0x3ff7ea9718 : { *(.g_4ea9718) }
  .g_4eaca30       0x3ff7eaca30 : { *(.g_4eaca30) }
}
