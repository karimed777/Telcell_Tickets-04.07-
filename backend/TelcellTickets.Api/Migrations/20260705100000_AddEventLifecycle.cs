using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using TelcellTickets.Api.Data;

#nullable disable

namespace TelcellTickets.Api.Migrations
{
    /// <inheritdoc />
    [DbContext(typeof(AppDbContext))]
    [Migration("20260705100000_AddEventLifecycle")]
    public partial class AddEventLifecycle : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "Events",
                type: "text",
                nullable: false,
                defaultValue: "Active");

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "NewStartsAt",
                table: "Events",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "DecisionDeadline",
                table: "Events",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Status",
                table: "Events");

            migrationBuilder.DropColumn(
                name: "NewStartsAt",
                table: "Events");

            migrationBuilder.DropColumn(
                name: "DecisionDeadline",
                table: "Events");
        }
    }
}
