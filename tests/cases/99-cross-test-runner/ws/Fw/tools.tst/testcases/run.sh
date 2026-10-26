#!/usr/bin/env atf-sh
atf_test_case uses_tool_and_its_library
uses_tool_and_its_library_body() { atf_check -s exit:0 -o match:"geo says 42" tool; }
atf_test_case sees_shared_data
sees_shared_data_body() {
    found=no
    old=$IFS; IFS=:
    for d in $BMK_SHAREDIR; do [ -f "$d/data.txt" ] && found=yes; done
    IFS=$old
    atf_check_equal "$found" yes
}
atf_init_test_cases() {
    atf_add_test_case uses_tool_and_its_library
    atf_add_test_case sees_shared_data
}
