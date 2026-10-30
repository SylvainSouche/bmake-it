// The same source for every target (see calc_ctest.c).
#include <atf-c++.hpp>

#include <fstream>
#include <stdexcept>

#include "calc.h"

ATF_TEST_CASE_WITHOUT_HEAD(adds);
ATF_TEST_CASE_BODY(adds)
{
    ATF_REQUIRE_EQ(5, calc_add(2, 3));
    ATF_REQUIRE_THROW(std::runtime_error, throw std::runtime_error("x"));
}

ATF_TEST_CASE_WITHOUT_HEAD(files);
ATF_TEST_CASE_BODY(files)
{
    // (a text-mode file: "\r\n" line ends on Windows, the same text)
    std::ofstream("out.txt") << "sum=" << calc_add(1, 1) << "\n";
    ATF_REQUIRE(atf::utils::file_exists("out.txt"));
    ATF_REQUIRE(atf::utils::grep_file("^sum=2$", "out.txt"));
    ATF_REQUIRE(atf::utils::compare_file("out.txt", "sum=2\n"));
    ATF_REQUIRE(!atf::utils::compare_file("out.txt", "sum=3\n"));
}

ATF_TEST_CASE(config);
ATF_TEST_CASE_HEAD(config)
{
    set_md_var("descr", "reads its metadata back");
}
ATF_TEST_CASE_BODY(config)
{
    ATF_REQUIRE_EQ("reads its metadata back", get_md_var("descr"));
}

ATF_INIT_TEST_CASES(tcs)
{
    ATF_ADD_TEST_CASE(tcs, adds);
    ATF_ADD_TEST_CASE(tcs, files);
    ATF_ADD_TEST_CASE(tcs, config);
}
