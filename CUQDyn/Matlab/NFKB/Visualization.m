% Visualization

for i=1:6    
    times = times(:);
    observed_values = observed_data(:,i);
    predicted_values = h_yout(:,i);
    true_data = h_xtrue(:,i);
    low_b = regionsi(:,i); % Lower bounds
    up_b = regionss(:,i); % Upper bounds
    
    fig=figure;
    
    width = 6;  % Anchura en pulgadas
    height = 6; % Altura en pulgadas

    set(fig, 'Units', 'Inches', 'Position', [0, 0, width, height]);

    % Plot of the upper bounds line
    plot(times, up_b, '-','Color',[0.286, 0.643, 0.678], 'LineWidth', 2);
    hold on;
    
    % Plot of the lower bounds line
    plot(times, low_b, '-','Color',[0.286, 0.643, 0.678], 'LineWidth', 2);
    
    fill([times; flipud(times)], [up_b; flipud(low_b)], [0.655, 0.867, 0.89], 'EdgeColor', 'none');
    
    % Plot of the true model
    plot(times_true, true_data, '--' ,'Color',[0.651 0.22 0],  'LineWidth', 2);
    
    % Plot of the predicted values
    plot(times_true, predicted_values, '--', 'Color', [0.404, 0.188, 0.6], 'LineWidth', 2);

     % Plot the observed data
    plot(times,observed_data(:,i),'.','Color', [0.157, 0.431, 0.078],'MarkerSize', 15);

    % Labels
    xlabel('Time');
    ylabel('State value');
    titleStr = sprintf('Predictive Regions State %i', i);
    title(titleStr);
    legend('', '','Predictive region', 'True model','Predicted values','Observed Values');
    grid on;
    hold off;

    axis square;

    set(fig, 'PaperPositionMode', 'auto');

end