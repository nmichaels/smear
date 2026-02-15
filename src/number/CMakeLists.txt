add_library(number STATIC)
target_include_directories(number PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_sources(number PRIVATE "number.c")
