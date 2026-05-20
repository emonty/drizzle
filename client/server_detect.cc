/* -*- mode: c++; c-basic-offset: 2; indent-tabs-mode: nil; -*-
 * vim:expandtab:shiftwidth=2:tabstop=2:smarttab:
 *
 *  Copyright (C) 2011 Andrew Hutchings
                  2012 Ajaya K. Agrawal
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include "client/client_priv.h"
#include "client/server_detect.h"

#include <cstdlib>
#include <iostream>

ServerDetect::ServerDetect(drizzle_con_st *connection) :
  type(SERVER_UNKNOWN_FOUND),
  version("")
{
  version= drizzle_con_server_version(connection);
  
  const char *safe_query = "SHOW VARIABLES LIKE 'vc_release_id'";
  drizzle_result_st* result= NULL;
  drizzle_return_t ret_ptr;
  result = drizzle_query_str(connection, NULL, safe_query, &ret_ptr);

  if(ret_ptr == DRIZZLE_RETURN_OK)
  {
    ret_ptr = drizzle_result_buffer(result);
    if(drizzle_result_row_count(result) > 0)
    {
      type = SERVER_DRIZZLE_FOUND;
    }
    else
    {
      type = SERVER_MYSQL_FOUND;
    }
  }
  else if(ret_ptr == DRIZZLE_RETURN_ERROR_CODE)
  {
    // The server answered with an error packet, so the connection
    // itself is healthy — we just could not read vc_release_id. An
    // authorization policy denying data_dictionary is the expected
    // cause (see the regex_policy / simple_user_policy suites, and
    // the drizzle/drizzledump tools connecting as a restricted
    // user). Only Drizzle has data_dictionary and those policy
    // plugins, so a probe that fails this way is still Drizzle.
    type = SERVER_DRIZZLE_FOUND;
  }
  else
  {
    // A non-error-code failure means the connection itself is
    // broken (server gone, dropped mid-probe, protocol error).
    // There is no server to detect, so report the libdrizzle error
    // and exit rather than guessing a type and masking the failure.
    std::cerr << "Server version not detectable: "
              << drizzle_con_error(connection) << std::endl;
    drizzle_result_free(result);
    std::exit(EXIT_FAILURE);
  }

  drizzle_result_free(result);    
}                
