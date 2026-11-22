# Provides ONNX Runtime from Microsoft's NuGet package (Microsoft.ML.OnnxRuntime).
#
# Universal Translator change: the upstream plugin downloads from
# github.com/microsoft/onnxruntime/releases, which no longer serves these files
# (HTTP 404, November 2026). NuGet has the same official binaries; the package
# is pinned by SHA-256.
#
# provide_onnxruntime_from_nuget(<dest dir> <runtime id>)
#   creates <dest dir>/include/*.h and <dest dir>/lib/<native libs>
set(UT_ORT_NUGET_VERSION "1.28.0")
set(UT_ORT_NUGET_SHA256 "769d1d3ea8ab6cd69f737c9dd4d4462aa4ad0ccfa106eaf506efc40d7bead5db")

function(provide_onnxruntime_from_nuget DEST RID)
  if(EXISTS "${DEST}/include/onnxruntime_cxx_api.h")
    return()
  endif()
  set(PKG "${CMAKE_BINARY_DIR}/ort_nuget/microsoft.ml.onnxruntime.${UT_ORT_NUGET_VERSION}.nupkg")
  set(X "${CMAKE_BINARY_DIR}/ort_nuget/x")
  if(NOT EXISTS "${PKG}")
    message(STATUS "Downloading ONNX Runtime ${UT_ORT_NUGET_VERSION} from NuGet")
    file(DOWNLOAD
      "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${UT_ORT_NUGET_VERSION}/microsoft.ml.onnxruntime.${UT_ORT_NUGET_VERSION}.nupkg"
      "${PKG}" EXPECTED_HASH SHA256=${UT_ORT_NUGET_SHA256} STATUS ST TLS_VERIFY ON)
    list(GET ST 0 CODE)
    if(NOT CODE EQUAL 0)
      message(FATAL_ERROR "ONNX Runtime NuGet download failed: ${ST}")
    endif()
  endif()
  if(NOT EXISTS "${X}/build/native/include/onnxruntime_cxx_api.h")
    file(MAKE_DIRECTORY "${X}")
    execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf "${PKG}" WORKING_DIRECTORY "${X}" RESULT_VARIABLE R)
    if(NOT R EQUAL 0)
      message(FATAL_ERROR "Could not extract ${PKG}")
    endif()
  endif()
  file(MAKE_DIRECTORY "${DEST}/include" "${DEST}/lib")
  file(GLOB HEADERS "${X}/build/native/include/*")
  file(COPY ${HEADERS} DESTINATION "${DEST}/include")
  file(GLOB LIBS "${X}/runtimes/${RID}/native/*")
  if(NOT LIBS)
    message(FATAL_ERROR "No ONNX Runtime binaries for ${RID} in the NuGet package")
  endif()
  file(COPY ${LIBS} DESTINATION "${DEST}/lib")
  # Linux: the library's SONAME is libonnxruntime.so.1
  if(EXISTS "${DEST}/lib/libonnxruntime.so")
    file(COPY_FILE "${DEST}/lib/libonnxruntime.so" "${DEST}/lib/libonnxruntime.so.1")
  endif()
endfunction()
