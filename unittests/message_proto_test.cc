/* -*- mode: c; c-basic-offset: 2; indent-tabs-mode: nil; -*-
 *  vim:expandtab:shiftwidth=2:tabstop=2:smarttab:
 *
 *  Copyright (C) 2026 OpenDev Contributors
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
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

#include <config.h>

#define BOOST_TEST_DYN_LINK
#include <boost/test/unit_test.hpp>

#include <drizzled/message/table.pb.h>
#include <google/protobuf/stubs/logging.h>

#include <string>

using namespace drizzled;

BOOST_AUTO_TEST_SUITE(MessageProto)

static void fill_required_table_fields(message::Table &table)
{
  table.set_name("t1");
  table.set_schema("test");
  table.set_type(message::Table::STANDARD);
  table.mutable_engine()->set_name("InnoDB");
  table.set_creation_timestamp(0);
  table.set_update_timestamp(0);
}

BOOST_AUTO_TEST_CASE(required_default_field_must_be_present)
{
  message::Table table;
  table.set_name("t1");
  table.set_schema("test");
  table.set_type(message::Table::STANDARD);
  table.mutable_engine()->set_name("InnoDB");
  table.set_update_timestamp(0);

  BOOST_REQUIRE(! table.has_creation_timestamp());
  BOOST_REQUIRE_EQUAL(0U, table.creation_timestamp());
  BOOST_REQUIRE(! table.IsInitialized());

  table.set_creation_timestamp(0);
  BOOST_REQUIRE(table.has_creation_timestamp());
  BOOST_REQUIRE(table.IsInitialized());
}

BOOST_AUTO_TEST_CASE(nested_required_field_is_checked)
{
  message::Table table;
  fill_required_table_fields(table);
  table.mutable_engine()->clear_name();

  BOOST_REQUIRE(! table.engine().has_name());
  BOOST_REQUIRE(! table.IsInitialized());
}

BOOST_AUTO_TEST_CASE(parse_rejects_missing_required_field)
{
  message::Table table;
  fill_required_table_fields(table);
  table.clear_creation_timestamp();

  std::string payload;
  BOOST_REQUIRE(table.SerializePartialToString(&payload));

  {
    google::protobuf::LogSilencer silence_expected_parse_error;
    message::Table parsed;
    BOOST_REQUIRE(! parsed.ParseFromString(payload));
    BOOST_REQUIRE(! parsed.IsInitialized());
  }

  message::Table partial;
  BOOST_REQUIRE(partial.ParsePartialFromString(payload));
  BOOST_REQUIRE(! partial.IsInitialized());
}

BOOST_AUTO_TEST_SUITE_END()
