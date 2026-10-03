#!/usr/bin/env atf-sh
atf_test_case uses_utility
uses_utility_body() { atf_check -s exit:0 -o match:"tool says hi" tool; }
atf_test_case sees_framework_bin
sees_framework_bin_body() { atf_check -s exit:0 -o match:"hello from hello" hello; }
atf_test_case sees_shared_data
sees_shared_data_body() {
    found=no
    old=$IFS; IFS=:
    for d in $BMK_SHAREDIR; do [ -f "$d/data.txt" ] && found=yes; done
    IFS=$old
    atf_check_equal "$found" yes
}
atf_init_test_cases() {
    atf_add_test_case uses_utility
    atf_add_test_case sees_framework_bin
    atf_add_test_case sees_shared_data
}
