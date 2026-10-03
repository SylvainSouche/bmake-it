#!/usr/bin/env atf-sh
atf_test_case fine
fine_body() { atf_check_equal 1 1; }
atf_init_test_cases() { atf_add_test_case fine; }
