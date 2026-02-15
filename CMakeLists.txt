cmake_minimum_required(VERSION 4.2.3)

project(smear VERSION 0.1.1 LANGUAGES C)
add_subdirectory(src)

set(CPACK_PACKAGE_DESCRIPTION
  "Smear is the SMudge Environment And Runtime, a standard library for
the Smudge state machine programming language."
)
set(CPACK_RESOURCE_FILE_README "README.md")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "SMudge Environment and Runtime")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/smudgelang/smear/")
set(CPACK_RESOURCE_FILE_LICENSE "LICENSE")
set(CPACK_PACKAGE_CONTACT "Nathan Michaels <nathan@nmichaels.org>")

set(CPACK_DEBIAN_PACKAGE_DEPENDS "")

include(CPack)

