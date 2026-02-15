add_library(cancelq STATIC)
target_include_directories(cancelq PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(cancelq PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/posix)

target_sources(cancelq PRIVATE
  "posix/cancellable.c"
)

target_link_libraries(cancelq PRIVATE smeartime)
