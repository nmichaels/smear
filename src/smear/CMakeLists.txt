# The smeartime library probably ought to have its own directory.
add_library(smeartime STATIC)
target_include_directories(smeartime PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_sources(smeartime PRIVATE
  smeartime.c
)

if (WIN32)
  target_sources(smeartime PRIVATE
    "Windows_NT/smeartime-platform.c"
  )
elseif(LINUX)
  target_sources(smeartime PRIVATE
    "linux/smeartime-platform.c"
  )
else()
  message(FATAL_ERROR "Unsupported platform for smeartime.")
endif()

target_link_libraries(smeartime PRIVATE
  number
)

add_library(smear STATIC)

target_include_directories(smear PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/../../include"
)

target_include_directories(smear PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_sources(smear PRIVATE
  "smear.c"
  "posix/thread-utils.c"
)

target_sources(smear PUBLIC
  FILE_SET HEADERS
  BASE_DIRS "${CMAKE_SOURCE_DIR}/include"
  FILES
  "${CMAKE_SOURCE_DIR}/include/smear/smear.h"
  "${CMAKE_SOURCE_DIR}/include/smear/version.h"
)
  
target_link_libraries(smear PRIVATE
  cancelq
)
