# frozen_string_literal: true

module StaticPagesHelper
  extend ActionView::Helpers::NumberHelper

  def card_to(name, path, **options)
    badge = if options[:badge].present?
              badge_for(options[:badge], class: options[:subtle_badge].present? || options[:badge] == 0 ? "bg-muted h-fit" : "bg-accent h-fit")
            elsif options[:async_badge].present?
              turbo_frame_tag options[:async_badge], src: admin_task_size_path(task_name: options[:async_badge]) do
                badge_for "⏳", class: "bg-muted"
              end
            else
              content_tag(:div, "") # Empty div if no badge is present
            end
    pin = inline_icon("pin", class: "pin transition-opacity group-hover:opacity-100 absolute top-0 right-0", size: 24, ':color': "isPinned($el.closest('a').parentElement.id) ? 'orange' : 'var(--muted)'", '@click.prevent': "pin($el.closest('a').parentElement.id, $el.closest('.grid').id)", ":class": "isPinned($el.closest('a').parentElement.id) ? 'opacity-100' : 'opacity-0'")
    content_tag(:div, id: "card-#{name.parameterize}", class: "group relative") do
      link_to content_tag(:div,
                          [
                            content_tag(:strong, sanitize(name), class: "card-name"),
                            pin,
                            content_tag(:span, "", style: "flex-grow: 1"),
                            badge,
                            inline_icon("view-forward", size: 24, class: "ml-1 -mr-2 muted fill-current")
                          ].join.html_safe,
                          class: "card card--hover flex justify-between items-center"),
              path, class: "link-reset", method: options[:method]
    end
  end

  def flavor_text
    FlavorTextService.new(user: current_user).generate
  end


  def render_permissions(permissions, depth = 0)
    capture do
      permissions.each_with_index do |(k, v), i|

        # Nested title (for feature groups)
        if v.is_a?(Hash)
          concat(content_tag(:tr) do
            content_tag(:th, class: "h#{depth + 2} #{"pt3" unless i.zero?}", style: "padding-left: #{depth * 2}rem") do
              concat k

              if v[:_preface]
                concat content_tag(:span, v[:_preface], class: "muted regular pl2 h5")
              end
            end
          end)

          concat render_permissions(v, depth + 1)

        # Row for feature with permission icons
        elsif v.is_a?(Symbol)
          concat(content_tag(:tr) do
            concat content_tag(:th, k, class: "regular", style: "padding-left: #{depth * 2}rem")

            needed_role_num = OrganizerPosition.roles[v]

            OrganizerPosition.roles.each_value do |role_num|
              if role_num >= needed_role_num
                concat content_tag(:td, "✅")
              else
                concat content_tag(:td, "❌")
              end
            end
          end)
        end

      end
    end
  end
end
